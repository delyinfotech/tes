'use client';

import { UploadProvider } from '@/contexts/UploadContext';

export default function Providers({ children }: { children: React.ReactNode }) {
  return <UploadProvider>{children}</UploadProvider>;
}
