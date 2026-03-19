import { fetchWithRetry } from './apiWithRetry';
import { getCached, setCache } from './cache';

const getToken = () => localStorage.getItem('token');

interface ApiOptions {
  cacheKey?: string;
  cacheTTL?: number;
  method?: string;
  body?: any;
}

export async function apiClient<T = any>(
  url: string,
  options: ApiOptions = {}
): Promise<T> {
  const { cacheKey, cacheTTL = 300000, method = 'GET', body } = options;

  if (cacheKey && method === 'GET') {
    const cached = getCached<T>(cacheKey);
    if (cached) return cached;
  }

  const headers: Record<string, string> = {
    'Authorization': `Bearer ${getToken()}`,
    'Content-Type': 'application/json',
  };

  const fetchOptions: RequestInit = { method, headers };
  if (body) fetchOptions.body = JSON.stringify(body);

  const response = await fetchWithRetry(url, fetchOptions);

  if (!response.ok) {
    const errorData = await response.json().catch(() => ({}));
    throw new Error(errorData.detail || `Ошибка сервера: ${response.status}`);
  }

  const data = await response.json();

  if (cacheKey && method === 'GET') {
    setCache(cacheKey, data, cacheTTL);
  }

  return data as T;
}
