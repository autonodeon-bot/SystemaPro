import { useEffect, useId, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { X } from 'lucide-react';

interface Props {
  title: string;
  children: ReactNode;
  onClose: () => void;
  busy?: boolean;
  description?: string;
  footer?: ReactNode;
}

/** Native modal supplies focus containment, inert background and nested stacking. */
export default function Modal({ title, children, onClose, busy = false, description, footer }: Props) {
  const ref = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  useEffect(() => {
    const dialog = ref.current!;
    const previous = document.activeElement as HTMLElement | null;
    dialog.showModal();
    dialog.querySelector<HTMLElement>('[data-initial-focus]')?.focus();
    return () => { dialog.close(); previous?.focus(); };
  }, []);
  return createPortal(
    <dialog ref={ref} className="sp-dialog" aria-labelledby={titleId} aria-busy={busy}
      onCancel={event => { event.preventDefault(); if (!busy) onClose(); }}>
      <header className="sp-dialog__header">
        <div className="min-w-0"><h2 id={titleId}>{title}</h2>{description && <p>{description}</p>}</div>
        <button type="button" className="sp-icon-button" aria-label="Закрыть окно" disabled={busy} onClick={onClose}><X size={20} /></button>
      </header>
      <div className="sp-dialog__body">{children}</div>
      {footer && <footer className="sp-dialog__footer">{footer}</footer>}
    </dialog>, document.body,
  );
}
