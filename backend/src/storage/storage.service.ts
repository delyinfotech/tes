import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
  HeadObjectCommand,
  ListObjectsV2Command,
  CreateMultipartUploadCommand,
  UploadPartCommand,
  CompleteMultipartUploadCommand,
  AbortMultipartUploadCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Readable } from 'stream';

export interface UploadResult {
  key: string;
  bucket: string;
  size: number;
  etag: string;
  url: string;
}

export interface SignedUrlOptions {
  expiresIn?: number;
  responseContentDisposition?: string;
}

@Injectable()
export class StorageService {
  private readonly logger = new Logger(StorageService.name);
  private readonly s3Client: S3Client;
  private readonly s3PublicClient: S3Client;
  private readonly buckets: {
    originals: string;
    processed: string;
    artifacts: string;
  };
  private readonly cdnBaseUrl: string;

  constructor(private configService: ConfigService) {
    const endpoint = this.configService.get<string>('minio.endpoint');
    const accessKey = this.configService.get<string>('minio.accessKey');
    const secretKey = this.configService.get<string>('minio.secretKey');
    const useSSL = this.configService.get<boolean>('minio.useSSL');

    // Internal client for server-side operations
    this.s3Client = new S3Client({
      endpoint,
      region: 'us-east-1',
      credentials: {
        accessKeyId: accessKey,
        secretAccessKey: secretKey,
      },
      forcePathStyle: true,
      tls: useSSL,
    });

    // Public client for generating browser-accessible URLs
    this.cdnBaseUrl = this.configService.get<string>('cdn.baseUrl') || 'http://localhost:9000';
    this.s3PublicClient = new S3Client({
      endpoint: this.cdnBaseUrl,
      region: 'us-east-1',
      credentials: {
        accessKeyId: accessKey,
        secretAccessKey: secretKey,
      },
      forcePathStyle: true,
      tls: useSSL,
    });

    this.buckets = this.configService.get('minio.buckets');

    this.logger.log('Storage service initialized with MinIO');
  }

  async uploadFile(
    file: Buffer,
    key: string,
    bucket: string = this.buckets.originals,
    metadata?: Record<string, string>,
    contentType?: string,
  ): Promise<UploadResult> {
    try {
      const command = new PutObjectCommand({
        Bucket: bucket,
        Key: key,
        Body: file,
        ContentType: contentType || 'application/octet-stream',
        Metadata: metadata,
      });

      const response = await this.s3Client.send(command);

      this.logger.log(`File uploaded successfully: ${bucket}/${key}`);

      return {
        key,
        bucket,
        size: file.length,
        etag: response.ETag,
        url: this.getCDNUrl(bucket, key),
      };
    } catch (error) {
      this.logger.error(`Failed to upload file: ${error.message}`, error.stack);
      throw error;
    }
  }

  async getFile(key: string, bucket: string = this.buckets.originals): Promise<Buffer> {
    try {
      const command = new GetObjectCommand({
        Bucket: bucket,
        Key: key,
      });

      const response = await this.s3Client.send(command);
      const chunks: Uint8Array[] = [];

      for await (const chunk of response.Body as any) {
        chunks.push(chunk);
      }

      return Buffer.concat(chunks);
    } catch (error) {
      this.logger.error(`Failed to get file: ${error.message}`, error.stack);
      throw error;
    }
  }

  async deleteFile(key: string, bucket: string = this.buckets.originals): Promise<void> {
    try {
      const command = new DeleteObjectCommand({
        Bucket: bucket,
        Key: key,
      });

      await this.s3Client.send(command);
      this.logger.log(`File deleted successfully: ${bucket}/${key}`);
    } catch (error) {
      this.logger.error(`Failed to delete file: ${error.message}`, error.stack);
      throw error;
    }
  }

  async fileExists(key: string, bucket: string = this.buckets.originals): Promise<boolean> {
    try {
      const command = new HeadObjectCommand({
        Bucket: bucket,
        Key: key,
      });

      await this.s3Client.send(command);
      return true;
    } catch (error) {
      if (error.name === 'NotFound') {
        return false;
      }
      throw error;
    }
  }

  async getFileMetadata(
    key: string,
    bucket: string = this.buckets.originals,
  ): Promise<any> {
    try {
      const command = new HeadObjectCommand({
        Bucket: bucket,
        Key: key,
      });

      const response = await this.s3Client.send(command);
      return {
        size: response.ContentLength,
        contentType: response.ContentType,
        lastModified: response.LastModified,
        etag: response.ETag,
        metadata: response.Metadata,
      };
    } catch (error) {
      this.logger.error(`Failed to get file metadata: ${error.message}`, error.stack);
      throw error;
    }
  }

  async listFiles(
    prefix: string,
    bucket: string = this.buckets.originals,
    maxKeys: number = 1000,
  ): Promise<any[]> {
    try {
      const command = new ListObjectsV2Command({
        Bucket: bucket,
        Prefix: prefix,
        MaxKeys: maxKeys,
      });

      const response = await this.s3Client.send(command);
      return response.Contents || [];
    } catch (error) {
      this.logger.error(`Failed to list files: ${error.message}`, error.stack);
      throw error;
    }
  }

  async getSignedUrl(
    key: string,
    bucket: string = this.buckets.processed,
    options: SignedUrlOptions = {},
  ): Promise<string> {
    try {
      const command = new GetObjectCommand({
        Bucket: bucket,
        Key: key,
        ResponseContentDisposition: options.responseContentDisposition,
      });

      // Use public client to generate browser-accessible URLs with correct signature
      const url = await getSignedUrl(this.s3PublicClient, command, {
        expiresIn: options.expiresIn || 3600, // 1 hour default
      });

      return url;
    } catch (error) {
      this.logger.error(`Failed to generate signed URL: ${error.message}`, error.stack);
      throw error;
    }
  }

  getCDNUrl(bucket: string, key: string): string {
    return `${this.cdnBaseUrl}/${bucket}/${key}`;
  }

  /**
   * Generate a presigned URL for direct browser upload to S3/MinIO
   * Supports files up to 5GB with single PUT request
   */
  async getPresignedUploadUrl(
    key: string,
    bucket: string = this.buckets.originals,
    options: {
      contentType?: string;
      expiresIn?: number;
      metadata?: Record<string, string>;
    } = {},
  ): Promise<{ uploadUrl: string; key: string; bucket: string; expiresIn: number }> {
    try {
      const command = new PutObjectCommand({
        Bucket: bucket,
        Key: key,
        ContentType: options.contentType || 'application/octet-stream',
        Metadata: options.metadata,
      });

      const expiresIn = options.expiresIn || 3600; // 1 hour default
      const uploadUrl = await getSignedUrl(this.s3PublicClient, command, {
        expiresIn,
      });

      this.logger.log(`Generated presigned upload URL for: ${bucket}/${key}`);

      return {
        uploadUrl,
        key,
        bucket,
        expiresIn,
      };
    } catch (error) {
      this.logger.error(`Failed to generate presigned upload URL: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Upload file from stream (for server-side streaming uploads)
   */
  async uploadFileStream(
    stream: Readable,
    key: string,
    bucket: string = this.buckets.originals,
    options: {
      contentType?: string;
      contentLength?: number;
      metadata?: Record<string, string>;
    } = {},
  ): Promise<UploadResult> {
    try {
      const command = new PutObjectCommand({
        Bucket: bucket,
        Key: key,
        Body: stream,
        ContentType: options.contentType || 'application/octet-stream',
        ContentLength: options.contentLength,
        Metadata: options.metadata,
      });

      const response = await this.s3Client.send(command);

      this.logger.log(`Stream uploaded successfully: ${bucket}/${key}`);

      return {
        key,
        bucket,
        size: options.contentLength || 0,
        etag: response.ETag,
        url: this.getCDNUrl(bucket, key),
      };
    } catch (error) {
      this.logger.error(`Failed to upload stream: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Initialize multipart upload for very large files (>5GB)
   */
  async initMultipartUpload(
    key: string,
    bucket: string = this.buckets.originals,
    contentType?: string,
  ): Promise<{ uploadId: string; key: string; bucket: string }> {
    try {
      const command = new CreateMultipartUploadCommand({
        Bucket: bucket,
        Key: key,
        ContentType: contentType || 'application/octet-stream',
      });

      const response = await this.s3Client.send(command);

      this.logger.log(`Initiated multipart upload for: ${bucket}/${key}`);

      return {
        uploadId: response.UploadId,
        key,
        bucket,
      };
    } catch (error) {
      this.logger.error(`Failed to init multipart upload: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Generate presigned URL for a single part in multipart upload
   */
  async getPresignedPartUrl(
    key: string,
    uploadId: string,
    partNumber: number,
    bucket: string = this.buckets.originals,
    expiresIn: number = 3600,
  ): Promise<string> {
    try {
      const command = new UploadPartCommand({
        Bucket: bucket,
        Key: key,
        UploadId: uploadId,
        PartNumber: partNumber,
      });

      const url = await getSignedUrl(this.s3PublicClient, command, { expiresIn });

      return url;
    } catch (error) {
      this.logger.error(`Failed to generate presigned part URL: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Complete multipart upload
   */
  async completeMultipartUpload(
    key: string,
    uploadId: string,
    parts: { ETag: string; PartNumber: number }[],
    bucket: string = this.buckets.originals,
  ): Promise<UploadResult> {
    try {
      const command = new CompleteMultipartUploadCommand({
        Bucket: bucket,
        Key: key,
        UploadId: uploadId,
        MultipartUpload: { Parts: parts },
      });

      const response = await this.s3Client.send(command);

      this.logger.log(`Completed multipart upload for: ${bucket}/${key}`);

      // Get file size after completion
      const metadata = await this.getFileMetadata(key, bucket);

      return {
        key,
        bucket,
        size: metadata.size,
        etag: response.ETag,
        url: this.getCDNUrl(bucket, key),
      };
    } catch (error) {
      this.logger.error(`Failed to complete multipart upload: ${error.message}`, error.stack);
      throw error;
    }
  }

  /**
   * Abort multipart upload
   */
  async abortMultipartUpload(
    key: string,
    uploadId: string,
    bucket: string = this.buckets.originals,
  ): Promise<void> {
    try {
      const command = new AbortMultipartUploadCommand({
        Bucket: bucket,
        Key: key,
        UploadId: uploadId,
      });

      await this.s3Client.send(command);

      this.logger.log(`Aborted multipart upload for: ${bucket}/${key}`);
    } catch (error) {
      this.logger.error(`Failed to abort multipart upload: ${error.message}`, error.stack);
      throw error;
    }
  }

  generateAssetKey(
    tenantId: string,
    assetId: string,
    filename: string,
    assetType: string,
  ): string {
    const extension = filename.split('.').pop();
    const timestamp = Date.now();
    const folder = this.getFolderByType(assetType);
    return `${folder}/${tenantId}/${assetId}/${timestamp}.${extension}`;
  }

  private getFolderByType(assetType: string): string {
    const typeMap: Record<string, string> = {
      video: 'videos',
      image: 'images',
      audio: 'audio',
      document: 'documents',
    };
    return typeMap[assetType] || 'misc';
  }
}
