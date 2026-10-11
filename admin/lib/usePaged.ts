"use client";

import { useCallback, useEffect, useState } from "react";
import { api, errorText } from "./api";
import type { Page } from "./types";
import { useApi } from "./useApi";

/** First page from the shared cache (instant when you come back); "Show more" appends later pages. */
export function usePaged<T>(basePath: string, limit = 20) {
  const sep = basePath.includes("?") ? "&" : "?";
  const first = useApi<Page<T>>(`${basePath}${sep}page=1&limit=${limit}`);
  const [extra, setExtra] = useState<{ base: string; rows: T[]; page: number }>({ base: basePath, rows: [], page: 1 });
  const [loadingMore, setLoadingMore] = useState(false);
  const [moreError, setMoreError] = useState<string | null>(null);

  // A new search or filter starts again from page 1.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setExtra({ base: basePath, rows: [], page: 1 });
  }, [basePath]);

  const more = useCallback(async () => {
    setLoadingMore(true);
    setMoreError(null);
    try {
      const next = extra.page + 1;
      const r = await api.get<Page<T>>(`${basePath}${sep}page=${next}&limit=${limit}`);
      setExtra((e) => (e.base === basePath ? { base: basePath, rows: [...e.rows, ...r.rows], page: next } : e));
    } catch (e) {
      setMoreError(errorText(e));
    } finally {
      setLoadingMore(false);
    }
  }, [basePath, sep, limit, extra.page]);

  const rows = first.data ? [...first.data.rows, ...(extra.base === basePath ? extra.rows : [])] : undefined;
  return { rows, total: first.data?.total ?? 0, error: first.error ?? moreError, loading: first.loading, loadingMore, more, reload: first.reload };
}
