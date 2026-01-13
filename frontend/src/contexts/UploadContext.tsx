'use client';

import React, { createContext, useContext, useState, useCallback, useRef } from 'react';
import { uploadAsset, Asset } from '@/lib/api';

export interface UploadItem {
  id: string;
  file: File;
  progress: number;
  status: 'pending' | 'uploading' | 'completed' | 'failed';
  error?: string;
  asset?: Asset;
  startedAt?: Date;
}

interface UploadContextType {
  uploads: UploadItem[];
  isUploading: boolean;
  totalProgress: number;
  addFiles: (files: File[], options?: { title?: string; folderId?: string }) => void;
  removeUpload: (id: string) => void;
  retryUpload: (id: string) => void;
  clearCompleted: () => void;
  cancelUpload: (id: string) => void;
}

const UploadContext = createContext<UploadContextType | null>(null);

export function useUpload() {
  const context = useContext(UploadContext);
  if (!context) {
    throw new Error('useUpload must be used within UploadProvider');
  }
  return context;
}

export function UploadProvider({ children }: { children: React.ReactNode }) {
  const [uploads, setUploads] = useState<UploadItem[]>([]);
  const abortControllers = useRef<Map<string, AbortController>>(new Map());

  const isUploading = uploads.some((u) => u.status === 'uploading');

  const totalProgress = uploads.length > 0
    ? Math.round(uploads.reduce((sum, u) => sum + u.progress, 0) / uploads.length)
    : 0;

  const processUpload = useCallback(async (uploadItem: UploadItem) => {
    const abortController = new AbortController();
    abortControllers.current.set(uploadItem.id, abortController);

    setUploads((prev) =>
      prev.map((u) =>
        u.id === uploadItem.id
          ? { ...u, status: 'uploading', progress: 0, startedAt: new Date() }
          : u
      )
    );

    try {
      const asset = await uploadAsset(uploadItem.file, {
        title: uploadItem.file.name.replace(/\.[^/.]+$/, ''),
        onProgress: (progress) => {
          setUploads((prev) =>
            prev.map((u) =>
              u.id === uploadItem.id ? { ...u, progress } : u
            )
          );
        },
      });

      setUploads((prev) =>
        prev.map((u) =>
          u.id === uploadItem.id
            ? { ...u, status: 'completed', progress: 100, asset }
            : u
        )
      );
    } catch (error) {
      if (error instanceof Error && error.message === 'Upload aborted') {
        setUploads((prev) => prev.filter((u) => u.id !== uploadItem.id));
      } else {
        setUploads((prev) =>
          prev.map((u) =>
            u.id === uploadItem.id
              ? {
                  ...u,
                  status: 'failed',
                  error: error instanceof Error ? error.message : 'Upload failed',
                }
              : u
          )
        );
      }
    } finally {
      abortControllers.current.delete(uploadItem.id);
    }
  }, []);

  const addFiles = useCallback(
    (files: File[], options?: { title?: string; folderId?: string }) => {
      const newUploads: UploadItem[] = files.map((file) => ({
        id: `${file.name}-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
        file,
        progress: 0,
        status: 'pending' as const,
      }));

      setUploads((prev) => [...prev, ...newUploads]);

      // Start uploading each file
      newUploads.forEach((upload) => {
        processUpload(upload);
      });
    },
    [processUpload]
  );

  const removeUpload = useCallback((id: string) => {
    const controller = abortControllers.current.get(id);
    if (controller) {
      controller.abort();
    }
    setUploads((prev) => prev.filter((u) => u.id !== id));
  }, []);

  const retryUpload = useCallback(
    (id: string) => {
      const upload = uploads.find((u) => u.id === id);
      if (upload && upload.status === 'failed') {
        processUpload({ ...upload, status: 'pending', progress: 0, error: undefined });
      }
    },
    [uploads, processUpload]
  );

  const clearCompleted = useCallback(() => {
    setUploads((prev) => prev.filter((u) => u.status !== 'completed'));
  }, []);

  const cancelUpload = useCallback((id: string) => {
    const controller = abortControllers.current.get(id);
    if (controller) {
      controller.abort();
    }
    setUploads((prev) => prev.filter((u) => u.id !== id));
  }, []);

  return (
    <UploadContext.Provider
      value={{
        uploads,
        isUploading,
        totalProgress,
        addFiles,
        removeUpload,
        retryUpload,
        clearCompleted,
        cancelUpload,
      }}
    >
      {children}
    </UploadContext.Provider>
  );
}
