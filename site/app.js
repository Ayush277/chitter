// Progressive enhancement only: copy buttons, the animated waveform bars, and the Pull-the-Thread demo.
(function () {
  var reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  var g = document.getElementById('bars');
  if (g) for (var i = 0; i < 40; i++) {
    var h = 14 + Math.abs(Math.sin(i * 0.7) * 56) + (i % 5) * 4;
    var r = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
    r.setAttribute('x', i * 6); r.setAttribute('width', 3.5); r.setAttribute('rx', 1.75);
    r.setAttribute('y', 45 - h / 2); r.setAttribute('height', h);
    r.style.animationDelay = (i * 0.045) + 's'; g.appendChild(r);
  }
  document.querySelectorAll('[data-copy]').forEach(function (b) {
    b.addEventListener('click', function () {
      navigator.clipboard.writeText(b.dataset.copy).then(function () {
        var t = b.textContent; b.textContent = 'Copied'; setTimeout(function () { b.textContent = t; }, 1400);
      });
    });
  });
  var box = document.getElementById('thread'), path = document.getElementById('tpath');
  if (!box || !path) return;
  function show(li) {
    var wanted = li.dataset.lines.split(',');
    var line = box.querySelector('[data-l="' + wanted[0] + '"]');
    box.querySelectorAll('.lines p').forEach(function (p) { p.classList.toggle('on', wanted.indexOf(p.dataset.l) > -1); });
    var b = box.getBoundingClientRect(), a = li.getBoundingClientRect(), l = line.getBoundingClientRect();
    var x1 = a.left - b.left, y1 = a.top + a.height / 2 - b.top, x2 = l.right - b.left - 6, y2 = l.top + l.height / 2 - b.top;
    if (innerWidth < 700) { x1 = a.left - b.left + 20; x2 = x1; }
    var dx = Math.max(40, Math.abs(x1 - x2) / 2);
    path.setAttribute('d', 'M' + x1 + ' ' + y1 + ' C' + (x1 - dx) + ' ' + y1 + ',' + (x2 + dx) + ' ' + y2 + ',' + x2 + ' ' + y2);
    path.classList.remove('draw');
    if (reduce) { path.style.transition = 'none'; path.classList.add('draw'); }
    else { void path.getBoundingClientRect(); path.classList.add('draw'); }
  }
  function clear() { path.classList.remove('draw'); box.querySelectorAll('.lines p').forEach(function (p) { p.classList.remove('on'); }); }
  box.querySelectorAll('.items li').forEach(function (li) {
    li.addEventListener('mouseenter', function () { show(li); });
    li.addEventListener('focus', function () { show(li); });
    li.addEventListener('click', function () { show(li); });
    li.addEventListener('mouseleave', clear); li.addEventListener('blur', clear);
  });
})();
