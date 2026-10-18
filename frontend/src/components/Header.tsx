import React from 'react';
import {
  Activity,
  Play,
  BarChart3,
  ShieldCheck,
  Clock,
  FileText,
  Binary,
  Cpu,
  CheckCircle2,
  AlertCircle
} from 'lucide-react';
import { SystemStatus } from '../types';

interface HeaderProps {
  currentTab: string;
  onSelectTab: (tab: string) => void;
  status: SystemStatus | null;
  loadingStatus: boolean;
}

export const Header: React.FC<HeaderProps> = ({
  currentTab,
  onSelectTab,
  status,
  loadingStatus
}) => {
  const tabs = [
    { id: 'overview', label: 'Overview', icon: Activity },
    { id: 'simulation', label: 'Simulation Runner', icon: Play },
    { id: 'waveform', label: 'Waveform Debugger', icon: Binary },
    { id: 'performance', label: 'Performance Analysis', icon: BarChart3 },
    { id: 'verification', label: 'Verification & Triage', icon: ShieldCheck },
    { id: 'history', label: 'Regression History', icon: Clock },
    { id: 'docs', label: 'Architecture & Specs', icon: FileText },
  ];

  const isSimulatorReady = status?.tools?.iverilog?.available && status?.tools?.vvp?.available;

  return (
    <header className="app-header">
      <div className="brand-section">
        <div className="brand-logo">DMA</div>
        <div>
          <div className="brand-title">
            DMA Lab <span className="brand-badge">DV Suite</span>
          </div>
        </div>
      </div>

      <nav className="nav-tabs">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = currentTab === tab.id;
          return (
            <button
              key={tab.id}
              className={`nav-tab-btn ${isActive ? 'active' : ''}`}
              onClick={() => onSelectTab(tab.id)}
            >
              <Icon size={16} />
              <span>{tab.label}</span>
            </button>
          );
        })}
      </nav>

      <div className="status-section">
        {loadingStatus ? (
          <div className="system-status-indicator" style={{ borderColor: 'var(--border-subtle)' }}>
            <span className="status-dot" style={{ background: 'var(--amber-warning)', boxShadow: '0 0 8px var(--amber-warning)' }} />
            <span>Auditing Toolchain...</span>
          </div>
        ) : isSimulatorReady ? (
          <div className="system-status-indicator">
            <span className="status-dot" />
            <span>Icarus v12 @ 100MHz | Ready</span>
          </div>
        ) : (
          <div className="system-status-indicator" style={{ borderColor: 'rgba(239, 68, 68, 0.4)', background: 'rgba(239, 68, 68, 0.1)' }}>
            <AlertCircle size={14} color="var(--ruby-error)" />
            <span style={{ color: '#f87171' }}>Simulator Offline</span>
          </div>
        )}
      </div>
    </header>
  );
};
