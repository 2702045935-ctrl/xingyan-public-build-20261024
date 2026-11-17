'use strict';

class ShardAuthorityRuntime {
  constructor(options) {
    const opts = options || {};
    this.store = opts.store;
    if (!this.store
        || typeof this.store.appendMessage !== 'function'
        || typeof this.store.allMessages !== 'function') {
      throw new Error('authority store is required');
    }
    this.isDirectChat = opts.isDirectChat;
    if (typeof this.isDirectChat !== 'function') {
      throw new Error('isDirectChat is required');
    }
    this.readEnabled = opts.readEnabled !== false;
    this.writeEnabled = opts.writeEnabled !== false;
    this.clearCursorCache = new Map();
    this.clearCursorCacheMax = Math.max(
      1000, Number(opts.clearCursorCacheMax) || 100000
    );
  }

  appliesTo(chatId) {
    return this.isDirectChat(String(chatId || '')) === true;
  }

  readMessages(chatId) {
    if (!this.readEnabled || !this.appliesTo(chatId)) return null;
    return this.store.allMessages(chatId);
  }

  appendMessage(chatId, message, chatState) {
    if (!this.writeEnabled || !this.appliesTo(chatId)) {
      return { status: 'bypass' };
    }
    return this.store.appendMessage(Object.assign({}, message || {}, {
      chatId: String(chatId || ''),
      chatState: chatState || {}
    }));
  }

  replaceMessages(chatId, messages, chatState) {
    if (!this.writeEnabled || !this.appliesTo(chatId)) {
      return { status: 'bypass' };
    }
    return this.store.replaceChatMessages(chatId, messages, chatState || {});
  }

  setClearCursor(userId, chatId, clearedSeq) {
    if (!this.writeEnabled || !this.appliesTo(chatId)) {
      return { status: 'bypass' };
    }
    const result = this.store.setClearCursor(chatId, userId, clearedSeq);
    if (result.status === 'applied' || result.status === 'duplicate') {
      const key = String(userId || '') + '|' + String(chatId || '');
      this.clearCursorCache.set(key, Number(result.clearedSeq) || 0);
      if (this.clearCursorCache.size > this.clearCursorCacheMax) {
        this.clearCursorCache.clear();
      }
    }
    return result;
  }

  clearCursor(userId, chatId) {
    if (!this.readEnabled || !this.appliesTo(chatId)) return 0;
    const key = String(userId || '') + '|' + String(chatId || '');
    if (this.clearCursorCache.has(key)) return this.clearCursorCache.get(key);
    const result = this.store.clearCursor(chatId, userId);
    const value = Number(result && result.clearedSeq) || 0;
    this.clearCursorCache.set(key, value);
    if (this.clearCursorCache.size > this.clearCursorCacheMax) {
      this.clearCursorCache.clear();
    }
    return value;
  }

  lastSequence(chatId) {
    return this.appliesTo(chatId) ? this.store.messages.lastSequence(chatId) : 0;
  }

  verify() {
    return this.store.verify();
  }

  close() {
    this.store.close();
  }
}

module.exports = { ShardAuthorityRuntime };
