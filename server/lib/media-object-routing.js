'use strict';

function isMediaObjectPath(method, pathname) {
  const path = String(pathname || '');
  if (/^\/(?:uploads|hls)\//.test(path)) return true;
  if (String(method || 'GET').toUpperCase() !== 'GET'
      && /^\/api\/upload(?:\/|$)/.test(path)) return true;
  return /^\/api\/feed(?:\/|$)/.test(path);
}

module.exports = { isMediaObjectPath };
