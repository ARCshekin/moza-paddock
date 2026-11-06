// Страница интерфейса. Отдаётся сервером как есть, без внешних зависимостей.
let webPage = """
<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MOZA</title>
<style>
  :root {
    --bg: #101215; --card: #191c21; --line: #2a2f37;
    --text: #e7eaef; --dim: #8b939f; --accent: #4c8dff; --ok: #3fb96a; --warn: #d98324;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 24px 16px 48px;
    background: var(--bg); color: var(--text);
    font: 14px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
  }
  .wrap { max-width: 560px; margin: 0 auto; display: flex; flex-direction: column; gap: 14px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 12px; padding: 16px; }
  .head { display: flex; align-items: center; gap: 10px; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: var(--dim); flex: none; }
  .dot.on { background: var(--ok); }
  .title { font-weight: 600; font-size: 15px; }
  .sub { color: var(--dim); font-size: 12px; }
  .label { color: var(--dim); font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
  .angle { font-size: 46px; font-weight: 300; font-variant-numeric: tabular-nums; margin: 6px 0 2px; }
  .track { position: relative; height: 12px; background: #0c0e11; border-radius: 6px; overflow: hidden; }
  .center { position: absolute; left: 50%; top: 0; bottom: 0; width: 1px; background: #3a4150; }
  .fill { position: absolute; top: 0; bottom: 0; background: var(--accent); opacity: .85; }
  .knob { position: absolute; top: -2px; width: 4px; height: 16px; border-radius: 2px; background: var(--accent); }
  .row { display: flex; align-items: center; gap: 10px; }
  .row + .row { margin-top: 10px; }
  .grow { flex: 1; }
  input[type=number] {
    width: 96px; padding: 8px 10px; font: inherit; font-variant-numeric: tabular-nums;
    color: var(--text); background: #0c0e11; border: 1px solid var(--line); border-radius: 8px;
  }
  button {
    padding: 8px 14px; font: inherit; font-weight: 500; color: var(--text);
    background: #232830; border: 1px solid var(--line); border-radius: 8px; cursor: pointer;
  }
  button:hover { background: #2b313b; }
  button:active { transform: translateY(1px); }
  button.primary { background: var(--accent); border-color: transparent; color: #fff; }
  button.primary:hover { background: #3d7ded; }
  .pedal + .pedal { margin-top: 10px; }
  .pedal .bar { height: 10px; background: #0c0e11; border-radius: 5px; overflow: hidden; }
  .pedal .bar span { display: block; height: 100%; background: var(--ok); width: 0; }
  .pedal .top { display: flex; justify-content: space-between; font-size: 12px; margin-bottom: 4px; }
  .pedal .top b { font-weight: 500; }
  .pedal .top i { color: var(--dim); font-style: normal; font-variant-numeric: tabular-nums; }
  .moving b { color: var(--accent); }
  .temps { display: flex; gap: 18px; flex-wrap: wrap; }
  .temps div { font-size: 12px; }
  .temps span { display: block; color: var(--dim); font-size: 10px; text-transform: uppercase; }
  .msg { color: var(--warn); font-size: 12px; min-height: 16px; }
  .hint { color: var(--dim); font-size: 12px; }
</style>
</head>
<body>
<div class="wrap">

  <div class="card head">
    <div class="dot" id="dot"></div>
    <div class="grow">
      <div class="title" id="model">MOZA</div>
      <div class="sub" id="port">поиск базы…</div>
    </div>
    <div class="sub" id="ffbstate"></div>
  </div>

  <div class="card">
    <div class="label">Положение руля</div>
    <div class="angle"><span id="deg">—</span><span style="font-size:22px;color:var(--dim)">°</span></div>
    <div class="track">
      <div class="center"></div>
      <div class="knob" id="knob" style="left:calc(50% - 2px)"></div>
    </div>
    <div class="row" style="margin-top:14px">
      <button class="primary" id="calib">Центрировать</button>
      <div class="hint grow">Выставьте руль ровно, затем нажмите</div>
    </div>
  </div>

  <div class="card">
    <div class="label">Угол поворота</div>
    <div class="row" style="margin-top:8px">
      <input type="number" id="angleInput" min="90" max="2700" step="10">
      <span class="sub">градусов</span>
      <button id="angleApply">Применить</button>
    </div>
    <div class="label" style="margin-top:18px">Сила отдачи</div>
    <div class="row" style="margin-top:8px">
      <input type="number" id="ffbInput" min="0" max="100" step="5">
      <span class="sub">%</span>
      <button id="ffbApply">Применить</button>
      <div class="hint grow" id="torque"></div>
    </div>
    <div class="row" style="margin-top:12px">
      <button id="pulse">Тестовое усилие</button>
      <div class="hint grow" id="pulseHint">Рывок фиксированной силы — разницу даёт настройка выше</div>
    </div>
  </div>

  <div class="card">
    <div class="label">Педали</div>
    <div id="pedals" style="margin-top:10px"></div>
    <div class="hint" id="pedalHint" style="margin-top:10px"></div>
    <div id="othersWrap" style="display:none">
      <div class="label" style="margin-top:18px">Прочие оси</div>
      <div id="others" style="margin-top:10px"></div>
    </div>
  </div>

  <div class="card">
    <div class="label">Температуры</div>
    <div class="temps" id="temps" style="margin-top:8px"></div>
  </div>

  <div class="msg" id="msg"></div>
  <div class="hint" style="text-align:center">сборка {{BUILD}}</div>
</div>

<script>
const el = (id) => document.getElementById(id);

// Опрос идёт каждые 100 мс. Если бы он перезаписывал поля ввода всегда, то
// стоило фокусу уйти на кнопку «Применить» — и в поле возвращалось бы старое
// значение, а кнопка отправляла бы его же. Поэтому: поле, которое человек
// правил руками, не трогаем до успешного применения.
let angleDirty = false;
let ffbDirty = false;
// Последнее значение, которое сообщила база. Нужно, чтобы отличить «база
// изменилась» от «просто очередной опрос с тем же значением».
let lastServerAngle = null;
let lastServerFFB = null;
el('angleInput').addEventListener('input', () => { angleDirty = true; });
el('ffbInput').addEventListener('input', () => { ffbDirty = true; });

// Газ и тормоз — определены на живом железе.
const PEDALS = { 0x32: 'Газ', 0x35: 'Тормоз' };
const WHEEL = 0x30;
const HAT = 0x39;   // не ось, а крестовина — в полоски не годится

async function poll() {
  try {
    const state = await (await fetch('/api/state')).json();
    render(state);
  } catch (error) {
    el('msg').textContent = 'Сервер не отвечает';
  }
}

function render(s) {
  el('dot').className = 'dot' + (s.connected ? ' on' : '');
  el('model').textContent = s.model || 'MOZA';
  el('port').textContent = s.connected ? s.port : 'база не найдена';

  const degrees = s.steeringDegrees;
  el('deg').textContent = (degrees === null || degrees === undefined)
    ? '—' : (degrees >= 0 ? '+' : '') + degrees.toFixed(1);

  const half = Math.max((s.angleSetting || 900) / 2, 1);
  const fraction = Math.min(Math.max(((degrees || 0) / half + 1) / 2, 0), 1);
  el('knob').style.left = 'calc(' + (fraction * 100) + '% - 2px)';

  // Поле трогаем ТОЛЬКО когда база сообщила новое значение — то есть когда оно
  // отличается от того, что база сообщала в прошлый раз. На обычном опросе
  // (значение то же) поле не переписывается вовсе, поэтому набранное вручную
  // никуда не денется. Флаг «правили руками» — дополнительная страховка на
  // случай, если значение сменится извне прямо во время набора.
  // Запомнить новое значение только вместе с его применением: иначе изменение,
  // пришедшее пока человек правит поле, было бы «съедено» и уже не применилось
  // бы после того, как правка закончится.
  if (s.angleSetting !== lastServerAngle && !angleDirty && s.angleSetting) {
    lastServerAngle = s.angleSetting;
    el('angleInput').value = s.angleSetting;
  }
  if (s.ffbStrength !== lastServerFFB && !ffbDirty
      && s.ffbStrength !== null && s.ffbStrength !== undefined) {
    lastServerFFB = s.ffbStrength;
    el('ffbInput').value = s.ffbStrength;
  }
  el('torque').textContent = (s.torque !== null && s.torque !== undefined)
    ? 'лимит момента ' + s.torque + ' %' : '';

  // Бит «эффект играет» эта прошивка не выставляет никогда, даже когда вал
  // реально крутится, поэтому показываем только состояние приводов.
  el('ffbstate').textContent = (s.actuatorsEnabled === null || s.actuatorsEnabled === undefined)
    ? '' : 'приводы ' + (s.actuatorsEnabled ? 'вкл' : 'выкл');

  // Кнопка недоступна, пока импульс идёт, и если канал отдачи не открылся.
  const pulseButton = el('pulse');
  pulseButton.disabled = s.pulsing || !s.forceFeedbackAvailable;
  if (!s.forceFeedbackAvailable) {
    el('pulseHint').textContent = 'Канал отдачи недоступен';
  } else if (s.pulsing) {
    el('pulseHint').textContent = 'Идёт импульс…';
  } else {
    el('pulseHint').textContent = 'Рывок фиксированной силы — разницу даёт настройка выше';
  }

  const axes = s.axes || [];

  function bar(label, axis, color) {
    return '<div class="pedal">'
      + '<div class="top"><b>' + label + '</b><i>' + axis.percent.toFixed(0) + ' %</i></div>'
      + '<div class="bar"><span style="width:' + axis.percent.toFixed(1) + '%'
      + (color ? ';background:' + color : '') + '"></span></div>'
      + '</div>';
  }

  const pedals = Object.keys(PEDALS)
    .map(usage => axes.find(a => a.usage === Number(usage)))
    .filter(Boolean);

  el('pedals').innerHTML = pedals
    .map(a => bar(PEDALS[a.usage], a, a.usage === 0x35 ? '#d9534f' : null))
    .join('');
  el('pedalHint').textContent = pedals.length
    ? '' : 'Педали не присылают данных — проверьте подключение.';

  // Остальные оси показываем только когда они реально шевелятся: иначе это
  // просто шум из неиспользуемых входов базы. Крестовину и руль исключаем.
  const others = axes.filter(a =>
    a.usage !== WHEEL && a.usage !== HAT && !(a.usage in PEDALS) && a.percent > 2);
  el('othersWrap').style.display = others.length ? 'block' : 'none';
  el('others').innerHTML = others.map(a => bar(a.name, a, '#8b939f')).join('');

  el('temps').innerHTML = (s.temperatures || [])
    .map(t => '<div><span>' + t.label + '</span>' + t.value + '</div>').join('');

  el('msg').textContent = s.message || '';
}

async function post(path) {
  const button = document.activeElement;
  if (button && button.tagName === 'BUTTON') button.disabled = true;
  try {
    await fetch(path, { method: 'POST' });
  } finally {
    if (button && button.tagName === 'BUTTON') button.disabled = false;
    poll();
  }
}

el('calib').onclick = () => post('/api/calibrate');
el('pulse').onclick = async () => {
  el('pulse').disabled = true;
  await fetch('/api/pulse', { method: 'POST' });
  poll();   // дальше блокировкой кнопки управляет флаг с сервера
};

async function applyAngle() {
  const value = el('angleInput').value;
  await post('/api/angle?value=' + encodeURIComponent(value));
  angleDirty = false;
}

async function applyFFB() {
  const value = el('ffbInput').value;
  await post('/api/ffb?value=' + encodeURIComponent(value));
  ffbDirty = false;
}

el('angleApply').onclick = applyAngle;
el('ffbApply').onclick = applyFFB;
el('angleInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') applyAngle(); });
el('ffbInput').addEventListener('keydown', (e) => { if (e.key === 'Enter') applyFFB(); });

poll();
setInterval(poll, 100);
</script>
</body>
</html>
"""
