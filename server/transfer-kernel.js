'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { Transform } = require('stream');
const { pipeline } = require('stream/promises');

const UPLOAD_MAGIC = Buffer.from('LUC1');
const DEFAULT_CHUNK_SIZE = 4 * 1024 * 1024;
const MAX_CHUNK_SIZE = 16 * 1024 * 1024;
const MAX_TRANSFER_BYTES = 2 * 1024 * 1024 * 1024;
const JOB_ID = /^xfer_[a-f0-9]{32}$/;

class TransferError extends Error {
  constructor(status, message, details) {
    super(message);
    this.name = 'TransferError';
    this.status = status;
    this.details = details || null;
  }
}

function sha256Text(value) {
  return /^[a-f0-9]{64}$/.test(String(value || '').toLowerCase());
}

function safeFilename(value) {
  const raw = path.basename(String(value || 'file')).replace(/[\u0000-\u001f]/g, '');
  return (raw || 'file').slice(0, 180);
}

function safeMime(value) {
  const mime = String(value || 'application/octet-stream').toLowerCase();
  return /^[a-z0-9][a-z0-9.+-]*\/[a-z0-9][a-z0-9.+-]*$/.test(mime)
    ? mime.slice(0, 120)
    : 'application/octet-stream';
}

function extensionFor(name, mime) {
  const fromName = path.extname(name).toLowerCase();
  if (/^\.[a-z0-9]{1,8}$/.test(fromName)) return fromName;
  if (mime === 'image/jpeg') return '.jpg';
  if (mime === 'image/png') return '.png';
  if (mime === 'video/quicktime') return '.mov';
  if (mime.startsWith('video/')) return '.mp4';
  if (mime === 'audio/mpeg') return '.mp3';
  if (mime.startsWith('audio/')) return '.m4a';
  return '.bin';
}

function counterAt(ivRaw, blockIndex) {
  const counter = Buffer.from(ivRaw);
  let add = blockIndex;
  for (let index = 15; index >= 0 && add > 0; index -= 1) {
    const sum = counter[index] + (add % 256);
    counter[index] = sum & 0xff;
    add = Math.floor(add / 256) + (sum > 255 ? 1 : 0);
  }
  return counter;
}

function atomicJsonWrite(file, value) {
  const temp = `${file}.${process.pid}.${crypto.randomBytes(4).toString('hex')}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(temp, file);
}

function createTransferKernel(options) {
  const dataDir = path.resolve(options.dataDir);
  const uploadDir = path.resolve(options.uploadDir);
  const secret = String(options.secret || '');
  const maxBytes = Math.min(
    MAX_TRANSFER_BYTES,
    Math.max(1, Number(options.maxBytes) || MAX_TRANSFER_BYTES)
  );
  const chunkSize = Math.min(
    MAX_CHUNK_SIZE,
    Math.max(256 * 1024, Number(options.chunkSize) || DEFAULT_CHUNK_SIZE)
  );
  const jobsDir = path.join(dataDir, 'transfers', 'jobs');
  const locks = new Map();

  fs.mkdirSync(jobsDir, { recursive: true });
  fs.mkdirSync(uploadDir, { recursive: true });

  function fileKey(fileName) {
    return crypto.createHmac('sha256', secret).update(`file:${fileName}`).digest();
  }

  function jobPath(id) {
    if (!JOB_ID.test(String(id || ''))) throw new TransferError(400, '传输任务编号不正确');
    return path.join(jobsDir, `${id}.json`);
  }

  function readJob(ownerId, id, required = true) {
    let job;
    try {
      job = JSON.parse(fs.readFileSync(jobPath(id), 'utf8'));
    } catch (_) {
      if (!required) return null;
      throw new TransferError(404, '传输任务不存在');
    }
    if (job.ownerId !== ownerId) throw new TransferError(404, '传输任务不存在');
    return job;
  }

  function saveJob(job) {
    job.updatedAt = new Date().toISOString();
    atomicJsonWrite(jobPath(job.id), job);
  }

  function publicStatus(job) {
    const received = Object.keys(job.chunks || {})
      .map(Number)
      .filter(Number.isInteger)
      .sort((a, b) => a - b);
    const missing = [];
    for (let index = 0; index < job.totalChunks; index += 1) {
      if (!job.chunks[String(index)]) missing.push(index);
    }
    return {
      id: job.id,
      status: job.status,
      size: job.size,
      chunkSize: job.chunkSize,
      totalChunks: job.totalChunks,
      receivedBytes: Object.values(job.chunks || {}).reduce(
        (sum, row) => sum + Math.max(0, Number(row.bytes) || 0),
        0
      ),
      storedBytes: Math.max(0, Number(job.storedBytes) || job.size),
      received,
      missing,
      sha256: job.sha256,
      mime: job.mime,
      name: job.name,
      skipTranscode: job.skipTranscode === true,
      url: job.url || '',
      error: job.error || '',
      createdAt: job.createdAt,
      updatedAt: job.updatedAt,
      completedAt: job.completedAt || ''
    };
  }

  function withJobLock(id, work) {
    const previous = locks.get(id) || Promise.resolve();
    const next = previous.catch(() => {}).then(work);
    locks.set(id, next);
    return next.finally(() => {
      if (locks.get(id) === next) locks.delete(id);
    });
  }

  function cleanupStaleJobs(now = Date.now()) {
    const uploadCutoff = now - 7 * 24 * 60 * 60 * 1000;
    let names = [];
    try {
      names = fs.readdirSync(jobsDir);
    } catch (_) {
      return;
    }
    for (const name of names) {
      if (!name.endsWith('.json')) continue;
      const file = path.join(jobsDir, name);
      let job = null;
      try {
        job = JSON.parse(fs.readFileSync(file, 'utf8'));
      } catch (_) {
        continue;
      }
      if (!job || job.status === 'ready') continue;
      const updated = Date.parse(job.updatedAt || job.createdAt || '');
      if (!Number.isFinite(updated) || updated >= uploadCutoff) continue;
      try { fs.unlinkSync(path.join(uploadDir, path.basename(job.fileName))); } catch (_) { }
      try { fs.unlinkSync(file); } catch (_) { }
    }
  }

  async function init(input) {
    cleanupStaleJobs();
    const ownerId = String(input.ownerId || '');
    if (!ownerId) throw new TransferError(401, '请先登录');
    const size = Number(input.size);
    if (!Number.isSafeInteger(size) || size <= 0) throw new TransferError(422, '文件大小不正确');
    if (size > maxBytes) throw new TransferError(413, '文件超过服务器允许的大小');
    const expectedSha = String(input.sha256 || '').toLowerCase();
    if (!sha256Text(expectedSha)) throw new TransferError(422, '文件总哈希不正确');

    const name = safeFilename(input.name);
    const mime = safeMime(input.mime);
    const id = `xfer_${crypto.randomBytes(16).toString('hex')}`;
    const fileName = `${id}${extensionFor(name, mime)}`;
    const iv = crypto.randomBytes(16);
    const finalFile = path.join(uploadDir, fileName);
    const totalChunks = Math.ceil(size / chunkSize);
    const now = new Date().toISOString();
    const job = {
      version: 1,
      id,
      ownerId,
      size,
      sha256: expectedSha,
      mime,
      name,
      fileName,
      iv: iv.toString('hex'),
      chunkSize,
      totalChunks,
      skipTranscode: input.skipTranscode === true,
      status: 'uploading',
      chunks: {},
      url: '',
      error: '',
      createdAt: now,
      updatedAt: now
    };

    const fd = fs.openSync(finalFile, 'w');
    try {
      fs.writeSync(fd, Buffer.concat([UPLOAD_MAGIC, iv]));
      fs.ftruncateSync(fd, 20 + size);
    } finally {
      fs.closeSync(fd);
    }
    saveJob(job);
    return publicStatus(job);
  }

  async function status(ownerId, id) {
    return publicStatus(readJob(ownerId, id));
  }

  async function putChunk(input) {
    const ownerId = String(input.ownerId || '');
    const id = String(input.id || '');
    const index = Number(input.index);
    const digest = String(input.sha256 || '').toLowerCase();
    if (!sha256Text(digest)) throw new TransferError(422, '分片哈希不正确');

    return withJobLock(id, async () => {
      const job = readJob(ownerId, id);
      if (job.status === 'ready') throw new TransferError(409, '文件已经上传完成', publicStatus(job));
      if (!Number.isInteger(index) || index < 0 || index >= job.totalChunks) {
        throw new TransferError(416, '分片编号超出范围');
      }
      const existing = job.chunks[String(index)];
      if (existing) {
        if (existing.sha256 !== digest) {
          throw new TransferError(409, '同一分片已存在但内容不同');
        }
        input.req.resume();
        return { duplicate: true, ...publicStatus(job) };
      }

      const offset = index * job.chunkSize;
      const expectedBytes = Math.min(job.chunkSize, job.size - offset);
      const contentLength = Number(input.req.headers['content-length']);
      if (Number.isFinite(contentLength) && contentLength > 0 && contentLength !== expectedBytes) {
        input.req.resume();
        throw new TransferError(422, '分片长度与任务声明不一致');
      }

      const hash = crypto.createHash('sha256');
      let received = 0;
      const meter = new Transform({
        transform(chunk, encoding, callback) {
          received += chunk.length;
          if (received > expectedBytes) {
            callback(new TransferError(413, '分片内容超过声明长度'));
            return;
          }
          hash.update(chunk);
          callback(null, chunk);
        }
      });
      const ivRaw = Buffer.from(job.iv, 'hex');
      const cipher = crypto.createCipheriv(
        'aes-256-ctr',
        fileKey(job.fileName),
        counterAt(ivRaw, Math.floor(offset / 16))
      );
      const output = fs.createWriteStream(path.join(uploadDir, job.fileName), {
        flags: 'r+',
        start: 20 + offset
      });
      try {
        await pipeline(input.req, meter, cipher, output);
      } catch (error) {
        if (error instanceof TransferError) throw error;
        throw new TransferError(422, '分片上传中断，请重试');
      }
      if (received !== expectedBytes) throw new TransferError(422, '分片不完整，请重试');
      if (hash.digest('hex') !== digest) throw new TransferError(422, '分片完整性校验失败');

      job.chunks[String(index)] = { bytes: received, sha256: digest };
      job.error = '';
      saveJob(job);
      return { duplicate: false, ...publicStatus(job) };
    });
  }

  async function verifyPlainHash(job) {
    const finalFile = path.join(uploadDir, job.fileName);
    const head = Buffer.alloc(20);
    const fd = fs.openSync(finalFile, 'r');
    try {
      if (fs.readSync(fd, head, 0, 20, 0) !== 20 || !head.subarray(0, 4).equals(UPLOAD_MAGIC)) {
        throw new TransferError(500, '上传文件头损坏');
      }
    } finally {
      fs.closeSync(fd);
    }
    const decipher = crypto.createDecipheriv(
      'aes-256-ctr',
      fileKey(job.fileName),
      head.subarray(4, 20)
    );
    const hash = crypto.createHash('sha256');
    const source = fs.createReadStream(finalFile, { start: 20 });
    for await (const chunk of source.pipe(decipher)) hash.update(chunk);
    return hash.digest('hex');
  }

  async function complete(input) {
    const ownerId = String(input.ownerId || '');
    const id = String(input.id || '');
    return withJobLock(id, async () => {
      const job = readJob(ownerId, id);
      if (job.status === 'ready') {
        return { duplicate: true, transfer: publicStatus(job) };
      }
      const missing = [];
      for (let index = 0; index < job.totalChunks; index += 1) {
        if (!job.chunks[String(index)]) missing.push(index);
      }
      if (missing.length) {
        throw new TransferError(409, '还有分片没有上传', {
          transfer: publicStatus(job),
          missing
        });
      }

      let actual = '';
      try {
        actual = await verifyPlainHash(job);
      } catch (error) {
        job.status = 'corrupt';
        job.error = error instanceof TransferError ? error.message : '文件完整性校验失败';
        saveJob(job);
        throw error instanceof TransferError
          ? error
          : new TransferError(422, job.error);
      }
      if (actual !== job.sha256) {
        job.status = 'corrupt';
        job.error = '文件总哈希不一致';
        saveJob(job);
        throw new TransferError(422, job.error);
      }

      const finalFile = path.join(uploadDir, job.fileName);
      if (typeof input.inspect === 'function') {
        try {
          await input.inspect(job, finalFile);
        } catch (error) {
          job.status = 'failed';
          job.error = error && error.message ? error.message : '文件处理失败';
          saveJob(job);
          throw error;
        }
      }
      job.status = 'ready';
      job.error = '';
      job.url = `/uploads/${job.fileName}`;
      job.completedAt = new Date().toISOString();
      saveJob(job);
      if (typeof input.onComplete === 'function') {
        await input.onComplete(job, finalFile);
      }
      return { duplicate: false, transfer: publicStatus(job) };
    });
  }

  async function cancel(ownerId, id) {
    return withJobLock(id, async () => {
      const job = readJob(ownerId, id);
      if (job.status === 'ready') throw new TransferError(409, '文件已经完成，不能取消');
      try { fs.unlinkSync(path.join(uploadDir, job.fileName)); } catch (_) { }
      job.status = 'cancelled';
      job.chunks = {};
      job.error = '用户取消上传';
      saveJob(job);
      return publicStatus(job);
    });
  }

  return {
    init,
    status,
    putChunk,
    complete,
    cancel,
    cleanupStaleJobs,
    publicStatus,
    TransferError
  };
}

module.exports = {
  createTransferKernel,
  TransferError,
  DEFAULT_CHUNK_SIZE,
  MAX_TRANSFER_BYTES
};
