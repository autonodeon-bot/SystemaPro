import { useState, useEffect, useCallback } from 'react';
import { Enterprise, Branch, Workshop } from '../types';
import { API_BASE } from '../constants';

interface UseHierarchyReturn {
  enterprises: Enterprise[];
  branches: Map<string, Branch[]>;
  workshops: Map<string, Workshop[]>;
  loading: boolean;
  error: string | null;
  loadBranches: (enterpriseId: string) => Promise<void>;
  loadWorkshops: (branchId: string) => Promise<void>;
  refresh: () => Promise<void>;
}

export function useHierarchy(): UseHierarchyReturn {
  const [enterprises, setEnterprises] = useState<Enterprise[]>([]);
  const [branches, setBranches] = useState<Map<string, Branch[]>>(new Map());
  const [workshops, setWorkshops] = useState<Map<string, Workshop[]>>(new Map());
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const getToken = () => localStorage.getItem('token');

  const loadEnterprises = useCallback(async () => {
    try {
      setLoading(true);
      const response = await fetch(`${API_BASE}/api/hierarchy/enterprises`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      if (response.ok) {
        const data = await response.json();
        setEnterprises(Array.isArray(data) ? data : data.items || []);
      }
    } catch (e) {
      setError('Ошибка загрузки предприятий');
    } finally {
      setLoading(false);
    }
  }, []);

  const loadBranches = useCallback(async (enterpriseId: string) => {
    try {
      const response = await fetch(`${API_BASE}/api/hierarchy/enterprises/${enterpriseId}/branches`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      if (response.ok) {
        const data = await response.json();
        setBranches(prev => {
          const next = new Map(prev);
          next.set(enterpriseId, Array.isArray(data) ? data : data.items || []);
          return next;
        });
      }
    } catch (e) {
      console.error('Error loading branches:', e);
    }
  }, []);

  const loadWorkshops = useCallback(async (branchId: string) => {
    try {
      const response = await fetch(`${API_BASE}/api/hierarchy/branches/${branchId}/workshops`, {
        headers: { 'Authorization': `Bearer ${getToken()}` }
      });
      if (response.ok) {
        const data = await response.json();
        setWorkshops(prev => {
          const next = new Map(prev);
          next.set(branchId, Array.isArray(data) ? data : data.items || []);
          return next;
        });
      }
    } catch (e) {
      console.error('Error loading workshops:', e);
    }
  }, []);

  const refresh = useCallback(async () => {
    await loadEnterprises();
  }, [loadEnterprises]);

  useEffect(() => {
    loadEnterprises();
  }, [loadEnterprises]);

  return { enterprises, branches, workshops, loading, error, loadBranches, loadWorkshops, refresh };
}
