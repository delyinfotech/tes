'use client';

import { useState } from 'react';
import {
  Upload,
  X,
  CheckCircle,
  XCircle,
  Loader2,
  ChevronUp,
  ChevronDown,
  RefreshCw,
  Trash2,
} from 'lucide-react';
import { useUpload } from '@/contexts/UploadContext';

export default function UploadIndicator() {
  const {
    uploads,
    isUploading,
    totalProgress,
    removeUpload,
    retryUpload,
    clearCompleted,
  } = useUpload();

  const [isExpanded, setIsExpanded] = useState(true);

  // Don't render if no uploads
  if (uploads.length === 0) {
    return null;
  }

  const completedCount = uploads.filter((u) => u.status === 'completed').length;
  const failedCount = uploads.filter((u) => u.status === 'failed').length;
  const uploadingCount = uploads.filter((u) => u.status === 'uploading').length;

  const formatFileSize = (bytes: number): string => {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(1))} ${sizes[i]}`;
  };

  const getFileIcon = (type: string) => {
    if (type.startsWith('video/')) return '🎬';
    if (type.startsWith('image/')) return '🖼️';
    if (type.startsWith('audio/')) return '🎵';
    return '📄';
  };

  return (
    <div className="fixed bottom-4 right-4 z-50 w-96 bg-background-medium rounded-xl shadow-2xl border border-background-light overflow-hidden">
      {/* Header - Always visible */}
      <div
        className="flex items-center justify-between p-3 bg-background-dark cursor-pointer"
        onClick={() => setIsExpanded(!isExpanded)}
      >
        <div className="flex items-center gap-3">
          {isUploading ? (
            <div className="relative">
              <Loader2 className="w-5 h-5 text-primary animate-spin" />
              <div className="absolute inset-0 flex items-center justify-center">
                <span className="text-[8px] font-bold text-primary">{totalProgress}</span>
              </div>
            </div>
          ) : failedCount > 0 ? (
            <XCircle className="w-5 h-5 text-status-failed" />
          ) : (
            <CheckCircle className="w-5 h-5 text-status-ready" />
          )}
          <div>
            <span className="text-sm font-medium text-white">
              {isUploading
                ? `Uploading ${uploadingCount} file${uploadingCount > 1 ? 's' : ''}...`
                : failedCount > 0
                ? `${failedCount} failed, ${completedCount} completed`
                : `${completedCount} upload${completedCount > 1 ? 's' : ''} complete`}
            </span>
            {isUploading && (
              <div className="w-32 h-1 mt-1 bg-background-light rounded-full overflow-hidden">
                <div
                  className="h-full bg-primary transition-all duration-300"
                  style={{ width: `${totalProgress}%` }}
                />
              </div>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          {completedCount > 0 && !isUploading && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                clearCompleted();
              }}
              className="p-1 text-text-muted hover:text-white transition-colors"
              title="Clear completed"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          )}
          {isExpanded ? (
            <ChevronDown className="w-5 h-5 text-text-muted" />
          ) : (
            <ChevronUp className="w-5 h-5 text-text-muted" />
          )}
        </div>
      </div>

      {/* Expanded file list */}
      {isExpanded && (
        <div className="max-h-64 overflow-y-auto">
          {uploads.map((upload) => (
            <div
              key={upload.id}
              className="flex items-center gap-3 p-3 border-b border-background-light last:border-0"
            >
              <span className="text-xl">{getFileIcon(upload.file.type)}</span>
              <div className="flex-1 min-w-0">
                <p className="text-sm text-white truncate" title={upload.file.name}>
                  {upload.file.name}
                </p>
                <div className="flex items-center gap-2">
                  <span className="text-xs text-text-muted">
                    {formatFileSize(upload.file.size)}
                  </span>
                  {upload.status === 'uploading' && (
                    <span className="text-xs text-primary">{upload.progress}%</span>
                  )}
                  {upload.status === 'failed' && upload.error && (
                    <span className="text-xs text-status-failed truncate" title={upload.error}>
                      {upload.error}
                    </span>
                  )}
                </div>
                {upload.status === 'uploading' && (
                  <div className="mt-1 h-1 bg-background-light rounded-full overflow-hidden">
                    <div
                      className="h-full bg-primary transition-all duration-300"
                      style={{ width: `${upload.progress}%` }}
                    />
                  </div>
                )}
              </div>
              <div className="flex items-center gap-1">
                {upload.status === 'uploading' && (
                  <Loader2 className="w-4 h-4 text-primary animate-spin" />
                )}
                {upload.status === 'completed' && (
                  <CheckCircle className="w-4 h-4 text-status-ready" />
                )}
                {upload.status === 'failed' && (
                  <>
                    <button
                      onClick={() => retryUpload(upload.id)}
                      className="p-1 text-text-muted hover:text-white transition-colors"
                      title="Retry"
                    >
                      <RefreshCw className="w-4 h-4" />
                    </button>
                    <XCircle className="w-4 h-4 text-status-failed" />
                  </>
                )}
                {upload.status !== 'uploading' && (
                  <button
                    onClick={() => removeUpload(upload.id)}
                    className="p-1 text-text-muted hover:text-white transition-colors"
                    title="Remove"
                  >
                    <X className="w-4 h-4" />
                  </button>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
