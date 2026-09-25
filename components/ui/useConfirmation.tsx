import { useEffect, useRef, useState } from 'react';
import Modal from './Modal';

export function useConfirmation() {
  const [message, setMessage] = useState<string | null>(null);
  const [options, setOptions] = useState<{ title?: string; confirmLabel?: string }>({});
  const resolve = useRef<((value: boolean) => void) | null>(null);
  useEffect(() => () => resolve.current?.(false), []);
  const finish = (value: boolean) => { resolve.current?.(value); resolve.current = null; setMessage(null); };
  const requestConfirmation = (text: string, config: { title?: string; confirmLabel?: string } = {}) => new Promise<boolean>(done => {
    resolve.current?.(false);
    resolve.current = done;
    setMessage(text);
    setOptions(config);
  });
  const confirmationDialog = message !== null && <Modal title={options.title ?? 'Подтвердите удаление'} onClose={() => finish(false)}
    footer={<>
      <button type="button" className="ind-btn" onClick={() => finish(false)}>Отмена</button>
      <button type="button" className={options.confirmLabel ? 'ind-btn ind-btn--primary' : 'ind-btn bg-red-600 text-white'} onClick={() => finish(true)}>{options.confirmLabel ?? 'Удалить'}</button>
    </>}><p className="whitespace-pre-wrap break-words">{message}</p></Modal>;
  return { requestConfirmation, confirmationDialog };
}
