/*
 * File: javascriptcore-url.js
 * ---------------------------
 * Layer: Benchmark
 * Description: The URL class Pele's sanitizeUrl (src/util/url.ts) asks for, which a JSContext lacks (WebKit's pages and
 *              Deno have it): http and https URLs parsed and written as the URL Standard does for them, enough for
 *              Pele to draw every documentation example as it does in Deno (PeleJavaScriptCoreComparison checks it).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 23/11/2026
 *
 * MIT licensed, as the package is. Pele makes a URL only of a link whose scheme is http or https, then sets its
 * protocol and hostname in lowercase and writes it; this class does those. Not done: hosts beyond ASCII (IDNA),
 * IPv4 written in other bases, and percent-encoded dots in paths, which the standard reads and this class leaves.
 */
var URL = (function () {
  'use strict';
  var defaultPorts = { http: '80', https: '443' };
  // The URL Standard's percent-encode sets, beyond the C0 controls and the code points past ~ (both always encoded).
  var pathSet = ' "#<>?`{}';
  var querySet = ' "#<>\'';
  var fragmentSet = ' "<>`';
  var forbiddenHost = /[\u0000\t\n\r #/:<>?@[\\\]^|%]/;

  function encoded(text, set) {
    var out = '';
    for (var index = 0; index < text.length; index++) {
      var code = text.charCodeAt(index);
      var character = text[index];
      if (code >= 0xd800 && code <= 0xdbff && index + 1 < text.length) {
        var next = text.charCodeAt(index + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          out += encodeURIComponent(text.slice(index, index + 2));
          index++;
          continue;
        }
      }
      if (code >= 0xd800 && code <= 0xdfff) out += '%EF%BF%BD';
      else if (code <= 0x1f || code > 0x7e) out += encodeURIComponent(character);
      else if (set.indexOf(character) >= 0) out += '%' + code.toString(16).toUpperCase().padStart(2, '0');
      else out += character;
    }
    return out;
  }

  function decodedHost(text) {
    var host;
    try {
      host = decodeURIComponent(text);
    } catch (error) {
      host = text;
    }
    return host.toLowerCase();
  }

  function URL(input) {
    var text = String(input).replace(/^[\u0000- ]+|[\u0000- ]+$/g, '').replace(/[\t\n\r]/g, '');
    var scheme = /^([A-Za-z][A-Za-z0-9+.-]*):/.exec(text);
    if (!scheme || defaultPorts[scheme[1].toLowerCase()] === undefined) throw new TypeError('Invalid URL: ' + text);
    this._scheme = scheme[1].toLowerCase();
    var rest = text.slice(scheme[0].length).replace(/\\/g, '/').replace(/^\/*/, '');
    var authorityEnd = rest.search(/[/?#]/);
    var authority = authorityEnd < 0 ? rest : rest.slice(0, authorityEnd);
    rest = authorityEnd < 0 ? '' : rest.slice(authorityEnd);
    var at = authority.lastIndexOf('@');
    this._userinfo = at < 0 ? '' : authority.slice(0, at);
    var hostAndPort = authority.slice(at + 1);
    var portMatch = /:(\d*)$/.exec(hostAndPort);
    this._hostname = decodedHost(portMatch ? hostAndPort.slice(0, portMatch.index) : hostAndPort);
    if (this._hostname === '' || forbiddenHost.test(this._hostname)) throw new TypeError('Invalid URL: ' + text);
    var port = portMatch ? portMatch[1].replace(/^0+(?=\d)/, '') : '';
    if (port !== '' && Number(port) > 65535) throw new TypeError('Invalid URL: ' + text);
    this._port = port === defaultPorts[this._scheme] ? '' : port;
    var hash = rest.indexOf('#');
    this._fragment = hash < 0 ? null : rest.slice(hash + 1);
    rest = hash < 0 ? rest : rest.slice(0, hash);
    var question = rest.indexOf('?');
    this._query = question < 0 ? null : rest.slice(question + 1);
    var path = question < 0 ? rest : rest.slice(0, question);
    var segments = [];
    var pieces = path.split('/').slice(1);
    pieces.forEach(function (piece, index) {
      var last = index === pieces.length - 1;
      if (piece === '..') {
        segments.pop();
        if (last) segments.push('');
      } else if (piece === '.') {
        if (last) segments.push('');
      } else {
        segments.push(encoded(piece, pathSet));
      }
    });
    this._path = '/' + segments.join('/');
  }

  Object.defineProperty(URL.prototype, 'protocol', {
    get: function () { return this._scheme + ':'; },
    set: function (value) {
      var scheme = String(value).split(':')[0].toLowerCase();
      if (defaultPorts[scheme] !== undefined) this._scheme = scheme;
    },
  });
  Object.defineProperty(URL.prototype, 'hostname', {
    get: function () { return this._hostname; },
    set: function (value) {
      var host = decodedHost(String(value));
      if (host !== '' && !forbiddenHost.test(host)) this._hostname = host;
    },
  });
  Object.defineProperty(URL.prototype, 'href', {
    get: function () {
      return this._scheme + '://' + (this._userinfo === '' ? '' : this._userinfo + '@') + this._hostname + (this._port === '' ? '' : ':' + this._port)
        + this._path + (this._query === null ? '' : '?' + encoded(this._query, querySet))
        + (this._fragment === null ? '' : '#' + encoded(this._fragment, fragmentSet));
    },
  });
  URL.prototype.toString = function () { return this.href; };
  return URL;
})();
