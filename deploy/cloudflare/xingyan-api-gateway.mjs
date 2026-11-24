import http from 'node:http';
import https from 'node:https';

const listenPort = Number(process.env.LISTEN_PORT || 18443);
const listenHost = process.env.LISTEN_HOST || '127.0.0.1';
const appPrefix = '/xy';
const appTarget = {
  protocol: process.env.APP_PROTOCOL || 'https',
  hostname: process.env.APP_HOST || '43.242.194.89',
  port: Number(process.env.APP_PORT || 8443),
  hostHeader: process.env.APP_HOST_HEADER || '43.242.194.89:8443',
};
const mailTarget = {
  protocol: process.env.MAIL_PROTOCOL || 'https',
  hostname: process.env.MAIL_HOST || '127.0.0.1',
  port: Number(process.env.MAIL_PORT || 443),
  hostHeader: process.env.MAIL_HOST_HEADER || 'mail.xingyanmail.site',
};
const agents = {
  'http:': new http.Agent({ keepAlive: true, maxSockets: 64 }),
  'https:': new https.Agent({
    keepAlive: true,
    maxSockets: 64,
    rejectUnauthorized: false,
  }),
};

function route(rawUrl) {
  const path = rawUrl || '/';
  const isApp =
    path === appPrefix || path.startsWith(`${appPrefix}/`);
  if (!isApp) {
    return { isApp: false, target: mailTarget, path };
  }
  return {
    isApp: true,
    target: appTarget,
    path: path.slice(appPrefix.length) || '/',
  };
}

function upstreamOptions(req, selected) {
  const headers = { ...req.headers };
  headers.host = selected.target.hostHeader;
  headers['x-forwarded-host'] = req.headers.host || '';
  headers['x-forwarded-proto'] =
    req.headers['x-forwarded-proto'] || 'https';
  return {
    protocol: `${selected.target.protocol}:`,
    hostname: selected.target.hostname,
    port: selected.target.port,
    method: req.method,
    path: selected.path,
    headers,
    agent: agents[`${selected.target.protocol}:`],
    rejectUnauthorized: false,
    timeout: 120000,
  };
}

const server = http.createServer((req, res) => {
  if (req.url === '/xy-gateway-health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, route: 'gateway' }));
    return;
  }

  const selected = route(req.url);
  const transport = selected.target.protocol === 'http' ? http : https;
  const upstream = transport.request(upstreamOptions(req, selected), (remote) => {
    res.writeHead(remote.statusCode || 502, remote.headers);
    remote.pipe(res);
  });
  upstream.on('timeout', () => upstream.destroy(new Error('upstream timeout')));
  upstream.on('error', (error) => {
    if (!res.headersSent) {
      res.writeHead(502, { 'content-type': 'application/json' });
    }
    res.end(JSON.stringify({ ok: false, error: 'gateway upstream unavailable' }));
    console.error(new Date().toISOString(), req.method, req.url, error.message);
  });
  req.pipe(upstream);
});

server.on('upgrade', (req, socket, head) => {
  const selected = route(req.url);
  if (!selected.isApp) {
    socket.destroy();
    return;
  }

  const transport = selected.target.protocol === 'http' ? http : https;
  const upstream = transport.request(upstreamOptions(req, selected));
  upstream.on('upgrade', (remote, remoteSocket, remoteHead) => {
    const headers = Object.entries(remote.headers)
      .map(([name, value]) => `${name}: ${value}`)
      .join('\r\n');
    socket.write(
      `HTTP/1.1 101 Switching Protocols\r\n${headers}\r\n\r\n`,
    );
    if (remoteHead.length) socket.write(remoteHead);
    if (head.length) remoteSocket.write(head);
    remoteSocket.pipe(socket);
    socket.pipe(remoteSocket);
  });
  upstream.on('response', (remote) => {
    const headers = Object.entries(remote.headers)
      .map(([name, value]) => `${name}: ${value}`)
      .join('\r\n');
    socket.write(
      `HTTP/1.1 ${remote.statusCode || 502} ${remote.statusMessage || ''}\r\n` +
        `${headers}\r\n\r\n`,
    );
    remote.pipe(socket);
  });
  upstream.on('timeout', () => upstream.destroy(new Error('upstream timeout')));
  upstream.on('error', (error) => {
    socket.destroy();
    console.error(new Date().toISOString(), 'UPGRADE', req.url, error.message);
  });
  upstream.end();
});

server.listen(listenPort, listenHost, () => {
  console.log(
    `xingyan api gateway listening on ${listenHost}:${listenPort}; ` +
      `app=${appTarget.hostname}:${appTarget.port}; ` +
      `mail=${mailTarget.hostname}:${mailTarget.port}`,
  );
});
