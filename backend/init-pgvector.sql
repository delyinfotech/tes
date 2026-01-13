-- ============================================================================
-- INIT-PGVECTOR.SQL
-- PostgreSQL Initialization Script for MediaX AI MAM System
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS vector;

-- Create custom types for the MediaX system
DO $$ 
BEGIN
    -- Asset status type
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'asset_status') THEN
        CREATE TYPE asset_status AS ENUM (
            'draft',
            'uploading',
            'processing',
            'ready',
            'error',
            'archived',
            'deleted'
        );
    END IF;

    -- Asset type/category
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'asset_category') THEN
        CREATE TYPE asset_category AS ENUM (
            'video',
            'audio',
            'image',
            'document',
            'archive',
            'other'
        );
    END IF;

    -- Media format/codec
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'media_format') THEN
        CREATE TYPE media_format AS ENUM (
            'mp4',
            'mov',
            'avi',
            'mkv',
            'webm',
            'flv',
            'wmv',
            'mpeg',
            'mp3',
            'wav',
            'aac',
            'flac',
            'jpg',
            'jpeg',
            'png',
            'webp',
            'gif',
            'bmp',
            'tiff',
            'pdf',
            'doc',
            'docx',
            'xls',
            'xlsx',
            'ppt',
            'pptx',
            'txt',
            'zip',
            'rar',
            '7z',
            'unknown'
        );
    END IF;

    -- Processing job status
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'job_status') THEN
        CREATE TYPE job_status AS ENUM (
            'pending',
            'processing',
            'completed',
            'failed',
            'cancelled'
        );
    END IF;

    -- User authentication provider
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'auth_provider') THEN
        CREATE TYPE auth_provider AS ENUM (
            'local',
            'google',
            'microsoft',
            'apple'
        );
    END IF;

    -- Tenant plan type
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'tenant_plan') THEN
        CREATE TYPE tenant_plan AS ENUM (
            'free',
            'starter',
            'professional',
            'enterprise',
            'custom'
        );
    END IF;

    -- Extraction type
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'extraction_type') THEN
        CREATE TYPE extraction_type AS ENUM (
            'metadata',
            'transcription',
            'face_detection',
            'object_detection',
            'scene_detection',
            'text_ocr',
            'audio_analysis',
            'video_analysis',
            'image_analysis'
        );
    END IF;

END $$;

-- ============================================================================
-- CREATE TABLES
-- ============================================================================

-- Tenants table
CREATE TABLE IF NOT EXISTS tenants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) UNIQUE NOT NULL,
    settings JSONB DEFAULT '{}',
    plan tenant_plan DEFAULT 'free',
    storage_limit_gb INTEGER DEFAULT 10,
    storage_used_gb DECIMAL(10,2) DEFAULT 0.0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT chk_storage_limit CHECK (storage_limit_gb > 0)
);

-- Roles table
CREATE TABLE IF NOT EXISTS roles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(50) UNIQUE NOT NULL,
    permissions TEXT[] DEFAULT '{}',
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    description TEXT,
    is_system_role BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_roles_tenant (tenant_id)
);

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(100) UNIQUE,
    password_hash VARCHAR(255),
    auth_provider auth_provider DEFAULT 'local',
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    avatar_url TEXT,
    bio TEXT,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    role_id UUID REFERENCES roles(id) ON DELETE SET NULL,
    preferences JSONB DEFAULT '{}',
    is_active BOOLEAN DEFAULT true,
    is_email_verified BOOLEAN DEFAULT false,
    mfa_enabled BOOLEAN DEFAULT false,
    mfa_secret VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    last_login_at TIMESTAMP WITH TIME ZONE,
    INDEX idx_users_tenant (tenant_id),
    INDEX idx_users_email (email),
    INDEX idx_users_username (username)
);

-- Folders table (hierarchical structure)
CREATE TABLE IF NOT EXISTS folders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL,
    parent_id UUID REFERENCES folders(id) ON DELETE CASCADE,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    is_public BOOLEAN DEFAULT false,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, parent_id, slug),
    INDEX idx_folders_tenant (tenant_id),
    INDEX idx_folders_parent (parent_id),
    INDEX idx_folders_slug (slug)
);

-- Assets table (main media assets)
CREATE TABLE IF NOT EXISTS assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    original_name VARCHAR(500) NOT NULL,
    file_name VARCHAR(500) NOT NULL,
    file_path TEXT NOT NULL,
    bucket_name VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100),
    asset_category asset_category NOT NULL,
    media_format media_format NOT NULL,
    duration INTEGER, -- in seconds
    width INTEGER,
    height INTEGER,
    bitrate INTEGER, -- in kbps
    frame_rate DECIMAL(5,2),
    status asset_status DEFAULT 'draft',
    folder_id UUID REFERENCES folders(id) ON DELETE SET NULL,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    uploaded_by UUID REFERENCES users(id) ON DELETE SET NULL,
    
    -- Metadata fields
    title VARCHAR(500),
    description TEXT,
    tags TEXT[] DEFAULT '{}',
    ai_tags TEXT[] DEFAULT '{}', -- AI-generated tags
    keywords TEXT[] DEFAULT '{}',
    language VARCHAR(10) DEFAULT 'en',
    
    -- Technical metadata
    metadata JSONB DEFAULT '{}',
    exif_data JSONB DEFAULT '{}',
    
    -- AI embeddings for semantic search (using pgvector)
    title_embedding vector(768), -- for title semantic search
    description_embedding vector(768), -- for description semantic search
    visual_embedding vector(512), -- for visual similarity search
    
    -- Processing info
    processing_job_id VARCHAR(255),
    processed_file_path TEXT,
    thumbnail_url TEXT,
    preview_url TEXT,
    
    -- Versioning
    version INTEGER DEFAULT 1,
    is_latest_version BOOLEAN DEFAULT true,
    previous_version_id UUID REFERENCES assets(id) ON DELETE SET NULL,
    
    -- Access control
    is_public BOOLEAN DEFAULT false,
    access_control JSONB DEFAULT '{}',
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    processed_at TIMESTAMP WITH TIME ZONE,
    
    -- Indexes
    INDEX idx_assets_tenant (tenant_id),
    INDEX idx_assets_folder (folder_id),
    INDEX idx_assets_status (status),
    INDEX idx_assets_category (asset_category),
    INDEX idx_assets_created_at (created_at DESC),
    INDEX idx_assets_tags (tags),
    INDEX idx_assets_ai_tags (ai_tags),
    INDEX idx_assets_uploaded_by (uploaded_by),
    
    -- Vector indexes for similarity search
    INDEX idx_assets_title_embedding ON assets USING ivfflat (title_embedding vector_cosine_ops),
    INDEX idx_assets_description_embedding ON assets USING ivfflat (description_embedding vector_cosine_ops),
    INDEX idx_assets_visual_embedding ON assets USING ivfflat (visual_embedding vector_cosine_ops)
);

-- Asset versions table (for version history)
CREATE TABLE IF NOT EXISTS asset_versions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    file_name VARCHAR(500) NOT NULL,
    file_path TEXT NOT NULL,
    file_size BIGINT NOT NULL,
    metadata JSONB DEFAULT '{}',
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (asset_id, version_number),
    INDEX idx_asset_versions_asset (asset_id)
);

-- Processing jobs table
CREATE TABLE IF NOT EXISTS processing_jobs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    job_type VARCHAR(100) NOT NULL,
    status job_status DEFAULT 'pending',
    input_path TEXT NOT NULL,
    output_path TEXT,
    parameters JSONB DEFAULT '{}',
    metadata JSONB DEFAULT '{}',
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    max_retries INTEGER DEFAULT 3,
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_processing_jobs_asset (asset_id),
    INDEX idx_processing_jobs_status (status),
    INDEX idx_processing_jobs_created_at (created_at DESC)
);

-- Metadata extraction results
CREATE TABLE IF NOT EXISTS metadata_extractions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    extraction_type extraction_type NOT NULL,
    extracted_data JSONB NOT NULL,
    confidence DECIMAL(5,4), -- confidence score 0-1
    model_version VARCHAR(50),
    processing_time_ms INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_metadata_extractions_asset (asset_id),
    INDEX idx_metadata_extractions_type (extraction_type)
);

-- Transcriptions table
CREATE TABLE IF NOT EXISTS transcriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    language VARCHAR(10) DEFAULT 'en',
    transcript TEXT NOT NULL,
    word_timestamps JSONB, -- array of {word: "", start: 0.0, end: 0.0}
    speaker_diarization JSONB, -- array of {speaker: "", segments: []}
    confidence DECIMAL(5,4),
    model_used VARCHAR(100),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_transcriptions_asset (asset_id)
);

-- Face detection results
CREATE TABLE IF NOT EXISTS face_detections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    frame_number INTEGER,
    timestamp_ms INTEGER,
    bounding_box JSONB NOT NULL, -- {x: 0, y: 0, width: 0, height: 0}
    landmarks JSONB, -- facial landmarks
    embedding vector(512), -- face embedding for recognition
    confidence DECIMAL(5,4),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_face_detections_asset (asset_id),
    INDEX idx_face_detections_timestamp (timestamp_ms)
);

-- Object detection results
CREATE TABLE IF NOT EXISTS object_detections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    frame_number INTEGER,
    timestamp_ms INTEGER,
    object_name VARCHAR(100) NOT NULL,
    bounding_box JSONB NOT NULL, -- {x: 0, y: 0, width: 0, height: 0}
    confidence DECIMAL(5,4),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_object_detections_asset (asset_id),
    INDEX idx_object_detections_object (object_name)
);

-- Scene detection results
CREATE TABLE IF NOT EXISTS scene_detections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    start_timestamp_ms INTEGER NOT NULL,
    end_timestamp_ms INTEGER NOT NULL,
    scene_type VARCHAR(100) NOT NULL,
    description TEXT,
    confidence DECIMAL(5,4),
    thumbnail_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_scene_detections_asset (asset_id),
    INDEX idx_scene_detections_timestamp (start_timestamp_ms)
);

-- AI model embeddings for similarity search
CREATE TABLE IF NOT EXISTS ai_embeddings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    model_name VARCHAR(100) NOT NULL,
    embedding vector NOT NULL, -- dimension varies by model
    embedding_type VARCHAR(50) NOT NULL, -- 'text', 'image', 'audio', 'video'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (asset_id, model_name, embedding_type),
    INDEX idx_ai_embeddings_asset (asset_id),
    INDEX idx_ai_embeddings_model (model_name)
);

-- Asset collections (playlists, albums, etc.)
CREATE TABLE IF NOT EXISTS collections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(255) NOT NULL,
    description TEXT,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    is_public BOOLEAN DEFAULT false,
    cover_asset_id UUID REFERENCES assets(id) ON DELETE SET NULL,
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (tenant_id, slug),
    INDEX idx_collections_tenant (tenant_id)
);

-- Collection items (many-to-many relationship)
CREATE TABLE IF NOT EXISTS collection_items (
    collection_id UUID REFERENCES collections(id) ON DELETE CASCADE,
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    position INTEGER DEFAULT 0,
    added_by UUID REFERENCES users(id) ON DELETE SET NULL,
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    PRIMARY KEY (collection_id, asset_id),
    INDEX idx_collection_items_collection (collection_id),
    INDEX idx_collection_items_asset (asset_id)
);

-- Usage analytics
CREATE TABLE IF NOT EXISTS asset_analytics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    asset_id UUID REFERENCES assets(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action VARCHAR(50) NOT NULL, -- 'view', 'download', 'share', 'edit'
    ip_address INET,
    user_agent TEXT,
    duration_seconds INTEGER, -- for views
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_asset_analytics_asset (asset_id),
    INDEX idx_asset_analytics_user (user_id),
    INDEX idx_asset_analytics_action (action),
    INDEX idx_asset_analytics_created_at (created_at)
);

-- Audit logs
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    tenant_id UUID REFERENCES tenants(id) ON DELETE CASCADE,
    action VARCHAR(100) NOT NULL,
    resource_type VARCHAR(50) NOT NULL,
    resource_id UUID,
    changes JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_logs_user (user_id),
    INDEX idx_audit_logs_tenant (tenant_id),
    INDEX idx_audit_logs_resource (resource_type, resource_id),
    INDEX idx_audit_logs_created_at (created_at DESC)
);

-- ============================================================================
-- FUNCTIONS AND TRIGGERS
-- ============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply updated_at triggers to all tables that need it
CREATE TRIGGER update_tenants_updated_at BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_folders_updated_at BEFORE UPDATE ON folders
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_assets_updated_at BEFORE UPDATE ON assets
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_processing_jobs_updated_at BEFORE UPDATE ON processing_jobs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_collections_updated_at BEFORE UPDATE ON collections
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to calculate folder path
CREATE OR REPLACE FUNCTION get_folder_path(folder_uuid UUID)
RETURNS TEXT AS $$
DECLARE
    path TEXT;
    current_id UUID;
    folder_name VARCHAR(255);
BEGIN
    path := '';
    current_id := folder_uuid;
    
    WHILE current_id IS NOT NULL LOOP
        SELECT name, parent_id INTO folder_name, current_id
        FROM folders WHERE id = current_id;
        
        IF path = '' THEN
            path := folder_name;
        ELSE
            path := folder_name || '/' || path;
        END IF;
    END LOOP;
    
    RETURN '/' || path;
END;
$$ LANGUAGE plpgsql;

-- Function for semantic similarity search
CREATE OR REPLACE FUNCTION semantic_search(
    query_embedding vector(768),
    similarity_threshold float DEFAULT 0.7,
    match_count int DEFAULT 10
)
RETURNS TABLE(
    asset_id UUID,
    title VARCHAR,
    similarity float
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.id,
        a.title,
        1 - (a.title_embedding <=> query_embedding) as similarity
    FROM assets a
    WHERE a.title_embedding IS NOT NULL
        AND 1 - (a.title_embedding <=> query_embedding) > similarity_threshold
    ORDER BY a.title_embedding <=> query_embedding
    LIMIT match_count;
END;
$$ LANGUAGE plpgsql;

-- Function for visual similarity search
CREATE OR REPLACE FUNCTION visual_similarity_search(
    query_embedding vector(512),
    similarity_threshold float DEFAULT 0.8,
    match_count int DEFAULT 10
)
RETURNS TABLE(
    asset_id UUID,
    file_name VARCHAR,
    similarity float
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        a.id,
        a.file_name,
        1 - (a.visual_embedding <=> query_embedding) as similarity
    FROM assets a
    WHERE a.visual_embedding IS NOT NULL
        AND 1 - (a.visual_embedding <=> query_embedding) > similarity_threshold
    ORDER BY a.visual_embedding <=> query_embedding
    LIMIT match_count;
END;
$$ LANGUAGE plpgsql;

-- Function to update storage usage
CREATE OR REPLACE FUNCTION update_tenant_storage()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE tenants
        SET storage_used_gb = storage_used_gb + (NEW.file_size / 1073741824.0) -- Convert bytes to GB
        WHERE id = NEW.tenant_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE tenants
        SET storage_used_gb = storage_used_gb - (OLD.file_size / 1073741824.0)
        WHERE id = OLD.tenant_id;
    ELSIF TG_OP = 'UPDATE' AND NEW.file_size != OLD.file_size THEN
        UPDATE tenants
        SET storage_used_gb = storage_used_gb - (OLD.file_size / 1073741824.0) + (NEW.file_size / 1073741824.0)
        WHERE id = NEW.tenant_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger for storage management
CREATE TRIGGER update_storage_on_asset_change
AFTER INSERT OR UPDATE OR DELETE ON assets
FOR EACH ROW EXECUTE FUNCTION update_tenant_storage();

-- ============================================================================
-- VIEWS
-- ============================================================================

-- View for asset details with folder info
CREATE OR REPLACE VIEW asset_details AS
SELECT
    a.*,
    f.name as folder_name,
    f.slug as folder_slug,
    u.email as uploaded_by_email,
    u.first_name as uploaded_by_first_name,
    u.last_name as uploaded_by_last_name,
    t.name as tenant_name,
    get_folder_path(a.folder_id) as folder_path
FROM assets a
LEFT JOIN folders f ON a.folder_id = f.id
LEFT JOIN users u ON a.uploaded_by = u.id
LEFT JOIN tenants t ON a.tenant_id = t.id;

-- View for processing queue
CREATE OR REPLACE VIEW processing_queue AS
SELECT
    pj.*,
    a.original_name,
    a.file_name,
    a.asset_category,
    u.email as submitted_by_email
FROM processing_jobs pj
JOIN assets a ON pj.asset_id = a.id
LEFT JOIN users u ON a.uploaded_by = u.id
WHERE pj.status IN ('pending', 'processing')
ORDER BY pj.created_at ASC;

-- View for storage usage by tenant
CREATE OR REPLACE VIEW tenant_storage_usage AS
SELECT
    t.id,
    t.name,
    t.slug,
    t.plan,
    t.storage_limit_gb,
    t.storage_used_gb,
    ROUND((t.storage_used_gb / NULLIF(t.storage_limit_gb, 0)) * 100, 2) as usage_percentage,
    COUNT(a.id) as total_assets,
    SUM(a.file_size) as total_bytes,
    MAX(a.created_at) as last_upload
FROM tenants t
LEFT JOIN assets a ON t.id = a.tenant_id
GROUP BY t.id, t.name, t.slug, t.plan, t.storage_limit_gb, t.storage_used_gb;

-- ============================================================================
-- DEFAULT DATA (Optional - only for development)
-- ============================================================================

-- Uncomment these lines for development/testing

-- INSERT INTO tenants (name, slug, plan, storage_limit_gb) 
-- VALUES ('Demo Tenant', 'demo', 'professional', 100)
-- ON CONFLICT (slug) DO NOTHING;

-- INSERT INTO roles (name, slug, permissions, is_system_role, description) 
-- VALUES 
--     ('Administrator', 'admin', ARRAY['*'], true, 'Full system access'),
--     ('Content Manager', 'manager', ARRAY['assets:read', 'assets:write', 'assets:delete', 'folders:manage'], false, 'Manage content and folders'),
--     ('Content Creator', 'creator', ARRAY['assets:read', 'assets:write'], false, 'Upload and manage own content'),
--     ('Reviewer', 'reviewer', ARRAY['assets:read', 'metadata:read'], false, 'Review and annotate content'),
--     ('Viewer', 'viewer', ARRAY['assets:read'], false, 'View content only')
-- ON CONFLICT (slug) DO NOTHING;

-- ============================================================================
-- INDEX OPTIMIZATION
-- ============================================================================

-- Create additional indexes for performance
CREATE INDEX IF NOT EXISTS idx_assets_tenant_status ON assets(tenant_id, status);
CREATE INDEX IF NOT EXISTS idx_assets_created_at_desc ON assets(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_assets_file_size ON assets(file_size);
CREATE INDEX IF NOT EXISTS idx_assets_mime_type ON assets(mime_type);
CREATE INDEX IF NOT EXISTS idx_users_tenant_role ON users(tenant_id, role_id);
CREATE INDEX IF NOT EXISTS idx_folders_tenant_parent ON folders(tenant_id, parent_id);
CREATE INDEX IF NOT EXISTS idx_processing_jobs_asset_status ON processing_jobs(asset_id, status);

-- Create GIN indexes for JSONB and array columns
CREATE INDEX IF NOT EXISTS idx_assets_metadata_gin ON assets USING GIN (metadata);
CREATE INDEX IF NOT EXISTS idx_assets_tags_gin ON assets USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_assets_ai_tags_gin ON assets USING GIN (ai_tags);

-- ============================================================================
-- FINAL MESSAGE
-- ============================================================================

DO $$ 
BEGIN
    RAISE NOTICE 'MediaX AI Database initialized successfully!';
    RAISE NOTICE 'Extensions enabled: uuid-ossp, vector';
    RAISE NOTICE 'Custom types created: asset_status, asset_category, media_format, job_status, auth_provider, tenant_plan, extraction_type';
    RAISE NOTICE 'Total tables created: 18';
    RAISE NOTICE 'Total functions created: 6';
    RAISE NOTICE 'Total triggers created: 7';
    RAISE NOTICE 'Total views created: 3';
END $$;