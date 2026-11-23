'use strict';

const { spawn } = require('child_process');

function createSshRunner(options) {
  const opts = options || {};
  const sshBin = String(opts.sshBin || 'ssh');
  const keyFile = String(opts.keyFile || '');
  const knownHostsFile = String(opts.knownHostsFile || '');
  const connectTimeout = Math.max(3, Number(opts.connectTimeout) || 10);
  return {
    async run(request) {
      const host = String(request && request.host || '');
      const user = String(request && request.user || 'root');
      const argv = Array.isArray(request && request.argv) ? request.argv : [];
      if (!host || !/^(?:\d{1,3}\.){3}\d{1,3}$/.test(host)
          && !/^[a-z0-9][a-z0-9.-]*$/i.test(host)) {
        throw new Error('invalid remote host');
      }
      if (!/^[a-z_][a-z0-9_-]*$/i.test(user)) throw new Error('invalid remote user');
      if (!argv.length || argv.some((value) => typeof value !== 'string')) {
        throw new Error('remote argv is invalid');
      }
      const args = [];
      if (keyFile) args.push('-i', keyFile);
      if (knownHostsFile) {
        args.push('-o', 'UserKnownHostsFile=' + knownHostsFile);
      }
      args.push(
        '-o', 'BatchMode=yes',
        '-o', 'StrictHostKeyChecking=yes',
        '-o', 'ConnectTimeout=' + connectTimeout,
        user + '@' + host
      );
      args.push(...argv);
      const stdout = await new Promise((resolve, reject) => {
        const child = spawn(sshBin, args, {
          stdio: ['ignore', 'pipe', 'pipe'],
          windowsHide: true
        });
        const out = [];
        const err = [];
        const timeout = setTimeout(() => {
          child.kill('SIGKILL');
          reject(new Error('remote command timeout: ' + request.purpose));
        }, Math.max(5000, Number(request.timeoutMs) || 300000));
        child.stdout.on('data', (chunk) => out.push(chunk));
        child.stderr.on('data', (chunk) => err.push(chunk));
        child.on('error', reject);
        child.on('close', (code) => {
          clearTimeout(timeout);
          const text = Buffer.concat(out).toString('utf8').trim();
          const failure = Buffer.concat(err).toString('utf8').trim();
          if (code !== 0) {
            reject(new Error((failure || text || 'ssh failed').slice(0, 4000)));
            return;
          }
          resolve(text);
        });
      });
      const lines = stdout.split(/\r?\n/).filter(Boolean);
      for (let index = lines.length - 1; index >= 0; index -= 1) {
        try {
          const parsed = JSON.parse(lines[index]);
          if (parsed && typeof parsed === 'object') return parsed;
        } catch (_) { /* command may log before its JSON receipt */ }
      }
      throw new Error('remote command returned no JSON receipt: ' + request.purpose);
    }
  };
}

module.exports = { createSshRunner };
