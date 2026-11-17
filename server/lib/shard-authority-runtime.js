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
