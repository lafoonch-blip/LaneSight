const { chromium } = require('playwright');
const http = require('http'), fs = require('fs'), path = require('path');
const root = __dirname;
const srv = http.createServer((q, s) => { const p = path.join(root, decodeURIComponent(q.url.split('?')[0]));
  if (!fs.existsSync(p)) { s.writeHead(404); return s.end(); }
  s.writeHead(200, { 'Content-Type': p.endsWith('.js') ? 'text/javascript' : 'text/html' }); fs.createReadStream(p).pipe(s); }).listen(8766);
(async () => {
  const b = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const jobs = JSON.parse(fs.readFileSync(process.argv[2]));
  for (const j of jobs) {
    const pg = await b.newPage({ viewport: { width: j.w, height: j.h }, deviceScaleFactor: 3 });
    pg.on('pageerror', e => console.log(j.name, 'ERR', e.message));
    await pg.goto(`http://localhost:8766/lane3d.html?w=${j.w}&h=${j.h}&d=${encodeURIComponent(JSON.stringify(j.data))}`);
    await pg.waitForFunction('window.__done', null, { timeout: 180000 });
    await pg.screenshot({ path: `${j.name}.png` });
    console.log(j.name, JSON.stringify(await pg.evaluate('window.__pts')));
  }
  await b.close(); srv.close();
})();
