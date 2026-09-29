import {createRequire} from 'node:module';
import path from 'node:path';
import {ROOT} from '../src/server.mjs';
const require = createRequire(import.meta.url);
const pkg = require.resolve('appium-webdriveragent/package.json', {paths: [path.join(ROOT, '.runtime/appium/node_modules/appium-xcuitest-driver')]});
console.log(path.join(path.dirname(pkg), 'WebDriverAgent.xcodeproj'));
