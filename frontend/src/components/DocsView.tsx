import React, { useEffect, useState } from 'react';
import { FileText, Download, CheckCircle2, BookOpen } from 'lucide-react';
import { ApiService } from '../services/api';
import { ArtifactItem } from '../types';

export const DocsView: React.FC = () => {
  const [artifacts, setArtifacts] = useState<ArtifactItem[]>([]);
  const [selectedDoc, setSelectedDoc] = useState<string>('interface_spec.md');
  const [docContent, setDocContent] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(true);

  useEffect(() => {
    const fetchArtifacts = async () => {
      try {
        const list = await ApiService.listArtifacts();
        setArtifacts(list);
        if (list.length > 0 && !list.find((a) => a.name === selectedDoc)) {
          setSelectedDoc(list[0].name);
        }
      } catch (err) {
        console.error(err);
      }
    };
    fetchArtifacts();
  }, []);

  useEffect(() => {
    if (!selectedDoc) return;
    const loadContent = async () => {
      setLoading(true);
      try {
        const text = await ApiService.getArtifact(selectedDoc);
        setDocContent(text);
      } catch (err: any) {
        setDocContent(`Error loading document: ${err.message}`);
      } finally {
        setLoading(false);
      }
    };
    loadContent();
  }, [selectedDoc]);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
      <div className="glass-card" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: '16px' }}>
        <div>
          <div style={{ display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '6px' }}>
            <span className="metric-pill pill-cyan">ENGINEERING SPECIFICATIONS</span>
            <span className="metric-pill pill-green">APPROVED ARTIFACTS</span>
          </div>
          <h2 style={{ fontSize: '1.4rem', fontWeight: 800, color: '#fff', fontFamily: 'var(--font-display)' }}>
            Architecture, Verification & Performance Documentation
          </h2>
          <div style={{ color: 'var(--text-muted)', fontSize: '0.85rem' }}>
            Authoritative hardware specifications, formal verification plans, and empirical analysis reports.
          </div>
        </div>

        <div style={{ display: 'flex', gap: '10px' }}>
          {artifacts.filter(a => a.name.endsWith('.md')).map((doc) => (
            <button
              key={doc.name}
              className={`btn-secondary ${selectedDoc === doc.name ? 'active' : ''}`}
              onClick={() => setSelectedDoc(doc.name)}
              style={{
                borderColor: selectedDoc === doc.name ? 'var(--amd-red)' : undefined,
                background: selectedDoc === doc.name ? 'rgba(237, 28, 36, 0.15)' : undefined
              }}
            >
              <FileText size={14} />
              <span>{doc.name.replace('.md', '')}</span>
            </button>
          ))}
        </div>
      </div>

      {/* Document Content Card */}
      <div className="glass-card">
        <div className="card-header">
          <div className="card-title">
            <BookOpen size={18} />
            Document Viewer: <span style={{ color: 'var(--cyan-accent)', fontFamily: 'var(--font-mono)' }}>{selectedDoc}</span>
          </div>
          {artifacts.find(a => a.name === selectedDoc) && (
            <span className="metric-pill pill-purple">
              {artifacts.find(a => a.name === selectedDoc)?.path}
            </span>
          )}
        </div>

        <div style={{
          background: '#07090d',
          border: '1px solid var(--border-subtle)',
          borderRadius: '8px',
          padding: '24px',
          fontFamily: 'var(--font-mono)',
          fontSize: '0.84rem',
          lineHeight: 1.6,
          color: '#c9d1d9',
          maxHeight: '650px',
          overflowY: 'auto',
          whiteSpace: 'pre-wrap'
        }}>
          {loading ? 'Loading document text...' : docContent}
        </div>
      </div>
    </div>
  );
};
