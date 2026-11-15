'use strict';

const { MessageReliabilityStore } = require('../lib/message-reliability');

const databaseFile = process.argv[2];
const worker = Number(process.argv[3]);
const count = Number(process.argv[4]);
const store = new MessageReliabilityStore({ databaseFile });
const sequences = [];

try {
  for (let index = 0; index < count; index += 1) {
    const result = store.reserveMessage({
      id: `probe-message-${worker}-${index}`,
      chatId: 'probe-chat',
      senderId: `probe-user-${worker}`,
      clientId: `probe-client-${worker}-${index}`,
      content: `probe-message-${worker}-${index}`
    });
    if (result.duplicate) throw new Error('unexpected duplicate reservation');
    sequences.push(result.seq);
  }
  process.stdout.write(JSON.stringify({ worker, sequences }));
} finally {
  store.close();
}
