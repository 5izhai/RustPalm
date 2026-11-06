import test from 'node:test';
import assert from 'node:assert/strict';
import { mapRemotePoint, clampOffset } from '../app/entry/src/main/ets/model/RemoteGeometry.ts';

test('letterboxing maps the centre and excludes black bars', () => {
  const centre = mapRemotePoint(200, 400, 400, 800, 1920, 1080, 1, 0, 0, 0, 0);
  assert.deepEqual([centre.x, centre.y, centre.inside], [960, 540, true]);
  assert.equal(mapRemotePoint(200, 10, 400, 800, 1920, 1080, 1, 0, 0, 0, 0).inside, false);
});
test('zoom and pan map to a display with a negative desktop origin', () => {
  const point = mapRemotePoint(200, 400, 400, 800, 1920, 1080, 2, 50, 0, -1920, 100);
  assert.deepEqual([point.x, point.y, point.inside], [-1080, 640, true]);
});
test('drag outside the viewport clamps to the last pixel', () => {
  const point = mapRemotePoint(1000, 900, 400, 800, 1920, 1080, 1, 0, 0, 0, 0);
  assert.deepEqual([point.x, point.y, point.inside], [1919, 1079, false]);
});
test('uninitialised surface cannot receive input and pan stays bounded', () => {
  assert.equal(mapRemotePoint(0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0).inside, false);
  assert.equal(clampOffset(200, 1000, 800), 100);
  assert.equal(clampOffset(-200, 1000, 800), -100);
  assert.equal(clampOffset(80, 400, 800), 0);
});

test('all four visible image corners map to the matching desktop corner', () => {
  // A 1920x1080 image fitted into 400x800 occupies y=287.5..512.5.
  // Stay just inside its right/bottom edges; those edges themselves are outside.
  const corners = [
    [0, 287.5, 0, 0],
    [399.9, 287.5, 1919, 0],
    [0, 512.49, 0, 1079],
    [399.9, 512.49, 1919, 1079],
  ];
  for (const [x, y, remoteX, remoteY] of corners) {
    const point = mapRemotePoint(x, y, 400, 800, 1920, 1080, 1, 0, 0, 0, 0);
    assert.deepEqual([point.x, point.y, point.inside], [remoteX, remoteY, true]);
  }
  assert.equal(mapRemotePoint(400, 400, 400, 800, 1920, 1080, 1, 0, 0, 0, 0).inside, false);
  assert.equal(mapRemotePoint(200, 512.5, 400, 800, 1920, 1080, 1, 0, 0, 0, 0).inside, false);
});

test('keyboard resizing uses the new viewport and letterbox position', () => {
  const original = mapRemotePoint(100, 100, 400, 800, 1920, 1080, 1, 0, 0, 0, 0);
  assert.equal(original.inside, false);
  // Reducing height to 400 moves the image top to 87.5 without changing its scale.
  const resized = mapRemotePoint(100, 100, 400, 400, 1920, 1080, 1, 0, 0, 0, 0);
  assert.deepEqual([resized.x, resized.y, resized.inside], [480, 60, true]);
  const centre = mapRemotePoint(200, 200, 400, 400, 1920, 1080, 1, 0, 0, 0, 0);
  assert.deepEqual([centre.x, centre.y], [960, 540]);
  // A further reduction to 200 is height-limited and introduces side bars.
  assert.equal(mapRemotePoint(20, 100, 400, 200, 1920, 1080, 1, 0, 0, 0, 0).inside, false);
  const shortCentre = mapRemotePoint(200, 100, 400, 200, 1920, 1080, 1, 0, 0, 0, 0);
  assert.deepEqual([shortCentre.x, shortCentre.y], [960, 540]);
});

test('zoomed panned points round-trip through a negative-origin desktop', () => {
  // A 960x540 image in 480x540 fits at 0.5x. At 2x zoom and offset(30,-20),
  // displayed pixels are 1:1 vp, with top-left(-210,-20) in the viewport.
  const samples = [[40, 80, -1670, 200], [270, 250, -1440, 370], [470, 500, -1240, 620]];
  for (const [x, y, expectedX, expectedY] of samples) {
    const point = mapRemotePoint(x, y, 480, 540, 960, 540, 2, 30, -20, -1920, 100);
    assert.deepEqual([point.x, point.y, point.inside], [expectedX, expectedY, true]);
    const renderedX = point.x + 1920 - 210;
    const renderedY = point.y - 100 - 20;
    assert.deepEqual([renderedX, renderedY], [x, y]);
  }
});

for (const viewport of [
  // Landscape with a 44vp tool strip: the 1920x1080 desktop is height-limited.
  { height: 321, left: 715 / 6, right: 4139 / 6, halfPixel: 107 / 720 },
  // The same page after the system keyboard resizes its remaining viewport.
  { height: 120, left: 1787 / 6, right: 3067 / 6, halfPixel: 1 / 18 },
]) {
  test(`landscape 809x${viewport.height} viewport maps desktop corners and centre after keyboard resize`, () => {
    const { height, left, right, halfPixel } = viewport;
    // Sample the centre of each corner pixel, rather than an edge whose
    // floating-point rounding could put it just outside the displayed image.
    const samples = [
      [left + halfPixel, halfPixel, 0, 0],
      [right - halfPixel, halfPixel, 1919, 0],
      [left + halfPixel, height - halfPixel, 0, 1079],
      [right - halfPixel, height - halfPixel, 1919, 1079],
      [404.5, height / 2, 960, 540],
    ];
    for (const [x, y, expectedX, expectedY] of samples) {
      const point = mapRemotePoint(x, y, 809, height, 1920, 1080, 1, 0, 0, 0, 0);
      assert.deepEqual([point.x, point.y, point.inside], [expectedX, expectedY, true]);
    }
    for (const x of [left - halfPixel, right + halfPixel]) {
      assert.equal(mapRemotePoint(x, height / 2, 809, height, 1920, 1080, 1, 0, 0, 0, 0).inside, false);
    }
  });
}

test('landscape keyboard resize excludes the old image area and recentres input', () => {
  // x=150 lies on the wide image before the keyboard appears, but on the new
  // left letterbox after it appears. The stale viewport must not remain active.
  assert.equal(mapRemotePoint(150, 60, 809, 321, 1920, 1080, 1, 0, 0, 0, 0).inside, true);
  assert.equal(mapRemotePoint(150, 60, 809, 120, 1920, 1080, 1, 0, 0, 0, 0).inside, false);
  const point = mapRemotePoint(404.5, 60, 809, 120, 1920, 1080, 1, 0, 0, 0, 0);
  assert.deepEqual([point.x, point.y, point.inside], [960, 540, true]);
});
