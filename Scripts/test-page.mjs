// Прогон настоящего кода страницы через сценарий пользователя.
// Никаких копий логики: скрипт берётся прямо с работающего сервера.
const html = await (await fetch('http://127.0.0.1:8765/')).text();
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

class FakeElement {
  constructor(id) {
    this.id = id; this.value = ''; this.textContent = ''; this.innerHTML = '';
    this.className = ''; this.style = {}; this.listeners = {}; this.tagName = 'INPUT';
    this.disabled = false;
  }
  addEventListener(type, handler) { (this.listeners[type] ||= []).push(handler); }
  fire(type, event = {}) { (this.listeners[type] || []).forEach(h => h(event)); }
}

const elements = new Map();
globalThis.document = {
  getElementById: (id) => {
    if (!elements.has(id)) elements.set(id, new FakeElement(id));
    return elements.get(id);
  },
  activeElement: null,
};
let pollFn = null;
globalThis.setInterval = (fn) => { pollFn = fn; return 0; };

// Управляемое состояние «базы».
let serverState = {
  connected: true, model: 'MOZA R5 Base', port: '/dev/cu.usbmodem101',
  angleSetting: 360, ffbStrength: 100, torque: 100,
  steeringRaw: 32768, steeringDegrees: 0, axes: [], temperatures: [],
  actuatorsEnabled: true, effectPlaying: false, message: null,
};
const posted = [];
globalThis.fetch = async (url, options) => {
  if (options && options.method === 'POST') {
    posted.push(url);
    const value = Number(new URL(url, 'http://x').searchParams.get('value'));
    if (url.includes('/api/angle')) serverState.angleSetting = value;
    if (url.includes('/api/ffb')) serverState.ffbStrength = value;
    return { json: async () => ({ ok: true }) };
  }
  return { json: async () => JSON.parse(JSON.stringify(serverState)) };
};

// Загружаем страницу: её собственный poll() выполнится сразу.
const module = await import('data:text/javascript,' + encodeURIComponent(script));
await new Promise(r => setTimeout(r, 20));

const angle = document.getElementById('angleInput');
const ffb = document.getElementById('ffbInput');
const checks = [];
const check = (name, ok, detail) => checks.push({ name, ok, detail });

check('после загрузки в поле угла значение с базы', angle.value == 360, `поле = ${angle.value}`);

// Несколько опросов без изменений — поле не должно шевелиться.
for (let i = 0; i < 3; i++) { await pollFn(); await new Promise(r => setTimeout(r, 5)); }
check('повторные опросы не переписывают поле', angle.value == 360, `поле = ${angle.value}`);

// Пользователь набирает 900 и уводит фокус (клик мимо поля).
angle.value = '900';
angle.fire('input');
document.activeElement = null;
for (let i = 0; i < 5; i++) { await pollFn(); await new Promise(r => setTimeout(r, 5)); }
check('НАБРАННОЕ 900 НЕ ОТКАТИЛОСЬ на 360', angle.value == 900, `поле = ${angle.value}`);

// Нажатие «Применить».
document.getElementById('angleApply').onclick();
await new Promise(r => setTimeout(r, 30));
check('на базу ушёл именно 900', posted.some(u => u.includes('value=900')), posted.join(' '));
for (let i = 0; i < 5; i++) { await pollFn(); await new Promise(r => setTimeout(r, 5)); }
check('после применения в поле осталось 900', angle.value == 900, `поле = ${angle.value}`);

// То же для силы отдачи.
ffb.value = '60';
ffb.fire('input');
for (let i = 0; i < 5; i++) { await pollFn(); await new Promise(r => setTimeout(r, 5)); }
check('набранная сила 60 не откатилась', ffb.value == 60, `поле = ${ffb.value}`);
document.getElementById('ffbApply').onclick();
await new Promise(r => setTimeout(r, 30));
check('на базу ушла сила 60', posted.some(u => u.includes('/api/ffb?value=60')), posted.join(' '));

// Внешнее изменение (например из CLI) должно подхватываться.
ffbDirtyReset: {
  serverState.angleSetting = 1080;
  for (let i = 0; i < 5; i++) { await pollFn(); await new Promise(r => setTimeout(r, 5)); }
  check('внешнее изменение угла подхватилось', angle.value == 1080, `поле = ${angle.value}`);
}

let failed = 0;
for (const c of checks) {
  if (!c.ok) failed++;
  console.log(`${c.ok ? '✓' : '✗'}  ${c.name}${c.ok ? '' : '  — ' + c.detail}`);
}
console.log(failed ? `\nПРОВАЛЕНО: ${failed} из ${checks.length}` : `\nВсе ${checks.length} проверок пройдены.`);
process.exit(failed ? 1 : 0);
