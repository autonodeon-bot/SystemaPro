import React from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';

interface ProtectedRouteProps {
  children: React.ReactNode;
  requiredRole?: string;
  requiredPermission?: string;
  allowedRoles?: string[];
}

const ProtectedRoute: React.FC<ProtectedRouteProps> = ({ 
  children, 
  requiredRole, 
  allowedRoles,
  requiredPermission 
}) => {
  const { isAuthenticated, hasRole, hasPermission, loading } = useAuth();
  const location = useLocation();

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-app-deep">
        <div className="text-center">
          <div className="inline-block w-8 h-8 border-4 border-accent border-t-transparent rounded-full animate-spin mb-4"></div>
          <p className="text-app-text3">Загрузка...</p>
        </div>
      </div>
    );
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" state={{ from: location }} replace />;
  }

  if ((requiredRole && !hasRole(requiredRole)) || (allowedRoles && !allowedRoles.some(role => hasRole(role)))) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-app-deep">
        <div className="text-center">
          <h2 className="text-2xl font-bold text-app-text mb-2">Доступ запрещен</h2>
          <p className="text-app-text3">Недостаточно прав для этого раздела</p>
        </div>
      </div>
    );
  }

  if (requiredPermission && !hasPermission(requiredPermission)) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-app-deep">
        <div className="text-center">
          <h2 className="text-2xl font-bold text-app-text mb-2">Доступ запрещен</h2>
          <p className="text-app-text3">Недостаточно прав доступа</p>
        </div>
      </div>
    );
  }

  return <>{children}</>;
};

export default ProtectedRoute;























