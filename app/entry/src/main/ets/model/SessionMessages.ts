export function authenticationAction(messageType: string): string {
  if (messageType === 'success') {
    return 'connected';
  }
  if (messageType === 'input-password' || messageType === 're-input-password') {
    return 'password';
  }
  if (messageType === 'input-2fa') {
    return '2fa';
  }
  if (messageType.startsWith('wait-remote-accept') || messageType === 'connecting' ||
      messageType === 'restarting') {
    return 'waiting';
  }
  if (messageType === 'wait-uac' || messageType === 'custom-uac-nocancel' ||
      messageType === 'custom-elevated-foreground-nocancel') {
    return 'notice';
  }
  return 'error';
}

// The core puts authentication failures in title; text can be empty or just
// "Do you want to enter again?". Never discard the actual failure reason.
export function sessionMessage(messageType: string, title: string, text: string): string {
  if (messageType === 're-input-password') {
    return '电脑访问密码错误，请输入电脑端 RustDesk 显示的临时密码或已设置的固定密码。';
  }
  if (messageType === 'input-password') {
    return '请输入电脑端 RustDesk 的访问密码（不是服务器公钥或 Windows 登录密码），也可在电脑端允许本次连接。';
  }
  if (title.length === 0) { return text; }
  if (text.length === 0 || text === title) { return title; }
  return title + '\n' + text;
}
