'use strict';

const { EventEmitter } = require('events');

function envelope(type, connectionId, payload) {
  return JSON.stringify(Object.assign({
    type,
    connectionId: String(connectionId || ''),
    at: Date.now()
  }, payload || {}));
}

function decodeEnvelope(text) {
  try {
    const row = JSON.parse(String(text || ''));
    if (!row || typeof row.type !== 'string') return null;
    return row;
  } catch (_) {
    return null;
  }
}

class VirtualGatewaySocket extends EventEmitter {
  constructor(options) {
    super();
    const opts = options || {};
    this.connectionId = String(opts.connectionId || '');
    this.remoteAddress = String(opts.remoteAddress || '');
    this.encrypted = true;
    this.destroyed = false;
    this.__appBuild = String(opts.appBuild || '').slice(0, 40);
    this.__deviceId = String(opts.deviceId || '').slice(0, 64);
    this.__kind = String(opts.kind || 'phone').slice(0, 20);
    this.onWrite = typeof opts.onWrite === 'function' ? opts.onWrite : () => {};
    this.onClose = typeof opts.onClose === 'function' ? opts.onClose : () => {};
  }

  setNoDelay() {}

  setKeepAlive() {}

  write(chunk) {
    if (this.destroyed) return false;
    try {
      return this.onWrite(Buffer.isBuffer(chunk) ? chunk : Buffer.from(String(chunk)));
    } catch (_) {
      this.destroy();
      return false;
    }
  }

  end() {
    if (this.destroyed) return;
    this.destroyed = true;
    this.onClose();
    this.emit('close');
  }

  destroy() {
    this.end();
  }
}

module.exports = {
  VirtualGatewaySocket,
  envelope,
  decodeEnvelope
};
