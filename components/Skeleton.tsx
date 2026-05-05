import React from 'react';

interface SkeletonProps {
  className?: string;
  width?: string | number;
  height?: string | number;
}

export const Skeleton: React.FC<SkeletonProps> = ({ className = '', width, height }) => (
  <div
    className={`animate-pulse bg-app-soft/50 rounded ${className}`}
    style={{ width: width ?? undefined, height: height ?? undefined }}
  />
);

export const SkeletonCard: React.FC = () => (
  <div className="bg-secondary/50 rounded-lg p-4 border border-app-line">
    <div className="flex gap-3">
      <Skeleton className="w-12 h-12 rounded-lg flex-shrink-0" />
      <div className="flex-1">
        <Skeleton className="h-5 w-3/4 mb-2" />
        <Skeleton className="h-4 w-1/2 mb-2" />
        <Skeleton className="h-4 w-full" />
      </div>
    </div>
  </div>
);

export const SkeletonTable: React.FC<{ rows?: number }> = ({ rows = 5 }) => (
  <div className="space-y-2">
    <Skeleton className="h-10 w-full" />
    {Array.from({ length: rows }).map((_, i) => (
      <Skeleton key={i} className="h-12 w-full" />
    ))}
  </div>
);
