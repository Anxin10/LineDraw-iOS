import {defineConfig} from '@playwright/test';
export default defineConfig({testDir:'./test',testMatch:'ui.spec.mjs',fullyParallel:false,workers:1,
  outputDir:'.runtime/ui-results',reporter:[['list']],
  use:{browserName:'chromium',channel:'chrome',headless:true,baseURL:'http://127.0.0.1:4790',viewport:{width:1440,height:1200}},
  webServer:{command:'node src/server.mjs',env:{LINEDRAW_PORT:'4790',LINEDRAW_DATA_DIR:'.runtime/ui-test-data'},url:'http://127.0.0.1:4790/api/status',reuseExistingServer:false}});
