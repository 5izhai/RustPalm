export class RemotePoint {
  x: number = 0;
  y: number = 0;
  inside: boolean = false;
}

// Input coordinates belong to the untransformed container, not its Surface.
export function mapRemotePoint(x: number, y: number, containerWidth: number,
  containerHeight: number, remoteWidth: number, remoteHeight: number,
  zoom: number, offsetX: number, offsetY: number, originX: number,
  originY: number): RemotePoint {
  const point = new RemotePoint();
  if (containerWidth <= 0 || containerHeight <= 0 || remoteWidth <= 0 ||
      remoteHeight <= 0 || zoom <= 0) {
    return point;
  }
  const scale = Math.min(containerWidth / remoteWidth, containerHeight / remoteHeight) * zoom;
  const localX = (x - containerWidth / 2 - offsetX) / scale + remoteWidth / 2;
  const localY = (y - containerHeight / 2 - offsetY) / scale + remoteHeight / 2;
  point.inside = localX >= 0 && localY >= 0 && localX < remoteWidth && localY < remoteHeight;
  point.x = originX + Math.max(0, Math.min(remoteWidth - 1, Math.floor(localX)));
  point.y = originY + Math.max(0, Math.min(remoteHeight - 1, Math.floor(localY)));
  return point;
}

export function clampOffset(value: number, contentSize: number, containerSize: number): number {
  const limit = Math.max(0, (contentSize - containerSize) / 2);
  return Math.max(-limit, Math.min(limit, value));
}
