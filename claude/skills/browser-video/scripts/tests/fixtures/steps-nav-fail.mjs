import base from './steps.mjs';

// Nothing listens on port 9, so navigation fails and Playwright reports the url.
export default { ...base, name: 'nav-fail', url: 'http://user:secret@127.0.0.1:9/?token=abc' };
