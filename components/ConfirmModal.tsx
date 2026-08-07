import React from 'react';
import { AlertTriangle, Trash2, FileCheck } from 'lucide-react';

interface ConfirmModalProps {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  variant?: 'danger' | 'warning' | 'primary';
  loading?: boolean;
}

export const ConfirmModal: React.FC<ConfirmModalProps> = ({
  open,
  onClose,
  onConfirm,
  title,
  message,
  confirmText = 'Подтвердить',
  cancelText = 'Отмена',
  variant = 'primary',
  loading = false,
}) => {
  if (!open) return null;

  const variantStyles = {
    danger: 'bg-red-600 hover:bg-red-700',
    warning: 'bg-yellow-600 hover:bg-yellow-700',
    primary: 'bg-accent hover:bg-accent/90',
  };

  const Icon = variant === 'danger' ? Trash2 : variant === 'warning' ? AlertTriangle : FileCheck;

  return (
    <div className="fixed inset-0 z-[9998] flex items-center justify-center p-4 bg-black/60" onClick={onClose}>
      <div
        className="bg-secondary rounded-xl border border-app-line shadow-xl max-w-md w-full p-6"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start gap-3 mb-4">
          <div
            className={`p-2 rounded-lg ${
              variant === 'danger' ? 'bg-red-500/20' : variant === 'warning' ? 'bg-yellow-500/20' : 'bg-accent/20'
            }`}
          >
            <Icon size={24} className={variant === 'danger' ? 'text-red-400' : variant === 'warning' ? 'text-yellow-400' : 'text-accent'} />
          </div>
          <div>
            <h3 className="text-lg font-semibold text-app-text">{title}</h3>
            <p className="text-app-text3 mt-1">{message}</p>
          </div>
        </div>
        <div className="flex gap-3 justify-end">
          <button
            onClick={onClose}
            className="px-4 py-2 rounded-lg bg-app-softer hover:bg-app-soft text-app-text font-medium"
          >
            {cancelText}
          </button>
          <button
            onClick={onConfirm}
            disabled={loading}
            className={`px-4 py-2 rounded-lg text-white font-medium disabled:opacity-50 ${variantStyles[variant]}`}
          >
            {loading ? '...' : confirmText}
          </button>
        </div>
      </div>
    </div>
  );
};
