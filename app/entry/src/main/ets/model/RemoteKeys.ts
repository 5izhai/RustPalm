// Names are the RustDesk KEY_MAP contract (src/client.rs), not native Windows
// virtual-key numbers. In particular VK_ESCAPE maps to ControlKey::Escape.
export class RemoteKeyCommand {
  name: string = '';
  down: boolean = false;
  press: boolean = true;
  alt: boolean = false;
  ctrl: boolean = false;
  shift: boolean = false;
  command: boolean = false;
}

export function toolbarKeyCommand(name: string, alt: boolean, ctrl: boolean,
  shift: boolean): RemoteKeyCommand {
  const command = new RemoteKeyCommand();
  switch (name) {
    case 'VK_ESCAPE':
    case 'VK_TAB':
    case 'VK_RETURN':
    case 'VK_BACK':
      command.name = name;
      break;
    case 'a': command.name = 'VK_A'; break;
    case 'c': command.name = 'VK_C'; break;
    case 'v': command.name = 'VK_V'; break;
    case 'z': command.name = 'VK_Z'; break;
    default: return command;
  }
  // Apply only the modifiers explicitly selected for this action, including
  // Ctrl+Esc and Ctrl+Shift+Esc. RemotePage clears the selection after one key.
  command.alt = alt;
  command.ctrl = ctrl;
  command.shift = shift;
  return command;
}

// Match RustDesk keyboard::client::event_lock_screen(): a dedicated control
// action, not an OS-specific shortcut. It must not inherit toolbar modifiers.
export function lockScreenCommand(): RemoteKeyCommand {
  const command = new RemoteKeyCommand();
  command.name = 'LOCK_SCREEN';
  command.down = true;
  command.press = false;
  return command;
}
