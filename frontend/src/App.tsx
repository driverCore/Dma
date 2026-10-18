import React, { useState, useEffect } from 'react';
import { Header } from './components/Header';
import { OverviewView } from './components/OverviewView';
import { SimulationView } from './components/SimulationView';
import { PerformanceView } from './components/PerformanceView';
import { VerificationView } from './components/VerificationView';
import { HistoryView } from './components/HistoryView';
import { DocsView } from './components/DocsView';
import { WaveformView } from './components/WaveformView';
import { ApiService } from './services/api';
import { SystemStatus } from './types';

export const App: React.FC = () => {
  const [currentTab, setCurrentTab] = useState<string>('overview');
  const [status, setStatus] = useState<SystemStatus | null>(null);
  const [loadingStatus, setLoadingStatus] = useState<boolean>(true);

  useEffect(() => {
    const fetchStatus = async () => {
      try {
        setLoadingStatus(true);
        const st = await ApiService.getStatus();
        setStatus(st);
      } catch (err) {
        console.error('Error fetching system status:', err);
      } finally {
        setLoadingStatus(false);
      }
    };
    fetchStatus();
  }, []);

  return (
    <div className="app-container">
      {/* Sticky Header with Navigation & Live Simulator Status */}
      <Header
        currentTab={currentTab}
        onSelectTab={setCurrentTab}
        status={status}
        loadingStatus={loadingStatus}
      />

      {/* Main Content Area */}
      <main className="main-content">
        {currentTab === 'overview' && (
          <OverviewView status={status} onNavigate={setCurrentTab} />
        )}
        {currentTab === 'simulation' && <SimulationView />}
        {currentTab === 'waveform' && <WaveformView />}
        {currentTab === 'performance' && <PerformanceView />}
        {currentTab === 'verification' && <VerificationView />}
        {currentTab === 'history' && <HistoryView />}
        {currentTab === 'docs' && <DocsView />}
      </main>

      {/* Footer */}
      <footer style={{
        borderTop: '1px solid var(--border-subtle)',
        padding: '16px 28px',
        background: 'var(--bg-glass)',
        backdropFilter: 'blur(10px)',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        fontSize: '0.78rem',
        color: 'var(--text-muted)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <span style={{ fontWeight: 700, color: 'var(--amd-red)' }}>DMA</span>
          <span>Design & Performance Verification Lab | Synthesizable Verilog Subsystem</span>
        </div>
        <div style={{ fontFamily: 'var(--font-mono)' }}>
          System Clock: 100.0 MHz | Simulator: Icarus Verilog v12.0 | Backend: FastAPI
        </div>
      </footer>
    </div>
  );
};

export default App;
