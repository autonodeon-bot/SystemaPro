"""
Система аутентификации и авторизации с RBAC
"""
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials, OAuth2PasswordBearer
from jose import JWTError, jwt
from datetime import datetime, timedelta
from typing import Optional, List, Dict
import os
import bcrypt
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
from database import get_db
from uuid import UUID
from models import (
    User as UserModel, UserEquipmentAccess, UserProjectAccess, Equipment, Project, Inspection, 
    Workshop, WorkshopEngineerAccess, ClientEngineerAccess, BranchEngineerAccess, 
    EquipmentTypeEngineerAccess, Branch
)

# Конфигурация JWT
SECRET_KEY = os.getenv("JWT_SECRET_KEY", "your-secret-key-change-in-production")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 часа

security = HTTPBearer()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="api/auth/login")

# Роли и их права доступа
ROLE_PERMISSIONS = {
    "admin": {
        "permissions": ["read", "write", "delete", "admin", "manage_users", "manage_equipment", "manage_projects"],
        "description": "Полный доступ ко всем функциям системы"
    },
    "chief_operator": {
        "permissions": ["read", "write", "delete", "manage_operators", "manage_engineers", "manage_equipment", "manage_projects"],
        "description": "Управление операторами и инженерами, доступ ко всем данным"
    },
    "operator": {
        "permissions": ["read", "write", "manage_engineers"],
        "description": "Управление инженерами на своих объектах"
    },
    "engineer": {
        "permissions": ["read", "write"],
        "description": "Доступ только к назначенным объектам"
    }
}

def hash_password(password: str) -> str:
    """Хеширование пароля с использованием bcrypt"""
    # Генерируем соль и хешируем пароль
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Проверка пароля с использованием bcrypt"""
    try:
        return bcrypt.checkpw(plain_password.encode('utf-8'), hashed_password.encode('utf-8'))
    except Exception as e:
        print(f"Ошибка проверки пароля: {e}")
        return False

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    """Создание JWT токена"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

async def get_user_by_username(db: AsyncSession, username: str) -> Optional[UserModel]:
    """Получить пользователя по username"""
    result = await db.execute(select(UserModel).where(UserModel.username == username))
    return result.scalar_one_or_none()

async def get_user_by_email(db: AsyncSession, email: str) -> Optional[UserModel]:
    """Получить пользователя по email"""
    result = await db.execute(select(UserModel).where(UserModel.email == email))
    return result.scalar_one_or_none()

async def get_user_by_id(db: AsyncSession, user_id: str) -> Optional[UserModel]:
    """Получить пользователя по ID"""
    try:
        from uuid import UUID
        user_uuid = UUID(user_id)
        result = await db.execute(select(UserModel).where(UserModel.id == user_uuid))
        return result.scalar_one_or_none()
    except:
        return None

async def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security), db: AsyncSession = Depends(get_db)):
    """Проверка JWT токена и получение пользователя из БД"""
    try:
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials",
                headers={"WWW-Authenticate": "Bearer"},
            )
        # Получаем пользователя из БД
        user = await get_user_by_username(db, username)
        if not user or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found or inactive",
                headers={"WWW-Authenticate": "Bearer"},
            )
        return user
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

def get_user_permissions(role: str) -> List[str]:
    """Получить права пользователя по роли"""
    role_data = ROLE_PERMISSIONS.get(role, {})
    return role_data.get("permissions", [])

def require_permission(permission: str):
    """Декоратор для проверки прав доступа"""
    async def permission_checker(user: UserModel = Depends(verify_token)):
        permissions = get_user_permissions(user.role)
        if permission not in permissions and "admin" not in permissions:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Permission '{permission}' required. Your role: {user.role}"
            )
        return user
    return permission_checker

def require_role(allowed_roles: List[str]):
    """Декоратор для проверки роли"""
    async def role_checker(user: UserModel = Depends(verify_token)):
        if user.role not in allowed_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Access denied. Required roles: {allowed_roles}"
            )
        return user
    return role_checker

async def check_equipment_access(db: AsyncSession, user: UserModel, equipment_id: str, required_permission: str = "read") -> bool:
    """Проверить доступ пользователя к оборудованию"""
    # Администратор, главный оператор и оператор имеют доступ ко всему
    if user.role in ["admin", "chief_operator", "operator"]:
        return True
    
    # Инженер - проверяем доступ через цех
    if user.role == "engineer" and user.engineer_id:
        try:
            from uuid import UUID
            from models import Equipment, WorkshopEngineerAccess
            eq_uuid = UUID(equipment_id)
            
            # Получаем оборудование
            result = await db.execute(
                select(Equipment).where(Equipment.id == eq_uuid)
            )
            equipment = result.scalar_one_or_none()
            
            # Проверяем доступ на всех уровнях иерархии
            # 1. Проверяем доступ через предприятие (Client)
            if equipment.workshop_id:
                # Получаем цех
                workshop_result = await db.execute(
                    select(Workshop).where(Workshop.id == equipment.workshop_id)
                )
                workshop = workshop_result.scalar_one_or_none()
                
                if workshop:
                    # Проверяем доступ к предприятию
                    if workshop.client_id:
                        client_access_result = await db.execute(
                            select(ClientEngineerAccess).where(
                                ClientEngineerAccess.client_id == workshop.client_id,
                                ClientEngineerAccess.engineer_id == user.engineer_id,
                                ClientEngineerAccess.is_active == True
                            )
                        )
                        if client_access_result.scalar_one_or_none():
                            return True
                    
                    # Проверяем доступ к филиалу
                    if workshop.branch_id:
                        branch_access_result = await db.execute(
                            select(BranchEngineerAccess).where(
                                BranchEngineerAccess.branch_id == workshop.branch_id,
                                BranchEngineerAccess.engineer_id == user.engineer_id,
                                BranchEngineerAccess.is_active == True
                            )
                        )
                        if branch_access_result.scalar_one_or_none():
                            return True
                    
                    # Проверяем доступ к цеху
                    access_result = await db.execute(
                        select(WorkshopEngineerAccess).where(
                            WorkshopEngineerAccess.workshop_id == equipment.workshop_id,
                            WorkshopEngineerAccess.engineer_id == user.engineer_id,
                            WorkshopEngineerAccess.is_active == True
                        )
                    )
                    access = access_result.scalar_one_or_none()
                    if access:
                        # Проверяем уровень доступа
                        if required_permission == "read":
                            return True
                        elif required_permission == "write" and access.access_type in ["read_write", "create_equipment"]:
                            return True
                        elif required_permission == "create" and access.access_type == "create_equipment":
                            return True
                    
                    # Проверяем доступ через тип оборудования
                    if equipment.type_id:
                        type_access_result = await db.execute(
                            select(EquipmentTypeEngineerAccess).where(
                                EquipmentTypeEngineerAccess.equipment_type_id == equipment.type_id,
                                EquipmentTypeEngineerAccess.engineer_id == user.engineer_id,
                                EquipmentTypeEngineerAccess.is_active == True
                            )
                        )
                        type_access = type_access_result.scalar_one_or_none()
                        if type_access:
                            if required_permission == "read":
                                return True
                            elif required_permission == "write" and type_access.access_type == "read_write":
                                return True
            
            # Также проверяем прямой доступ к оборудованию
            direct_result = await db.execute(
                select(UserEquipmentAccess).where(
                    UserEquipmentAccess.user_id == user.id,
                    UserEquipmentAccess.equipment_id == eq_uuid,
                    UserEquipmentAccess.is_active == True
                )
            )
            direct_access = direct_result.scalar_one_or_none()
            if direct_access:
                if required_permission == "write" and direct_access.access_type == "read_only":
                    return False
                return True
            return False
        except:
            return False
    
    return False

async def check_project_access(db: AsyncSession, user: UserModel, project_id: str, required_permission: str = "read") -> bool:
    """Проверить доступ пользователя к проекту"""
    # Администратор и главный оператор имеют доступ ко всему
    if user.role in ["admin", "chief_operator"]:
        return True
    
    # Оператор имеет доступ ко всему
    if user.role == "operator":
        return True
    
    # Инженер - проверяем доступ в таблице
    if user.role == "engineer":
        try:
            from uuid import UUID
            proj_uuid = UUID(project_id)
            result = await db.execute(
                select(UserProjectAccess).where(
                    UserProjectAccess.user_id == user.id,
                    UserProjectAccess.project_id == proj_uuid,
                    UserProjectAccess.is_active == True
                )
            )
            access = result.scalar_one_or_none()
            if access:
                if required_permission == "write" and access.access_type == "read_only":
                    return False
                return True
            return False
        except:
            return False
    
    return False

async def get_user_accessible_equipment_ids(db: AsyncSession, user: UserModel) -> List[str]:
    """Получить список ID оборудования, к которому есть доступ (многоуровневая иерархия)"""
    if user.role in ["admin", "chief_operator", "operator"]:
        # Получаем все оборудование
        result = await db.execute(select(Equipment.id))
        return [str(eq_id) for eq_id in result.scalars().all()]
    
    accessible_ids = set()
    
    # Для инженера - проверяем доступ на всех уровнях иерархии
    if user.role == "engineer" and user.engineer_id:
        from sqlalchemy import or_
        from uuid import UUID as UUIDType
        
        # 1. Доступ через предприятия (Client)
        client_result = await db.execute(
            select(ClientEngineerAccess.client_id).where(
                ClientEngineerAccess.engineer_id == user.engineer_id,
                ClientEngineerAccess.is_active == True
            )
        )
        client_ids = [str(id) for id in client_result.scalars().all()]
        
        # 2. Доступ через филиалы (Branch)
        branch_result = await db.execute(
            select(BranchEngineerAccess.branch_id).where(
                BranchEngineerAccess.engineer_id == user.engineer_id,
                BranchEngineerAccess.is_active == True
            )
        )
        branch_ids = [str(id) for id in branch_result.scalars().all()]
        
        # 3. Доступ через цеха (Workshop)
        workshop_result = await db.execute(
            select(WorkshopEngineerAccess.workshop_id).where(
                WorkshopEngineerAccess.engineer_id == user.engineer_id,
                WorkshopEngineerAccess.is_active == True
            )
        )
        workshop_ids = [str(id) for id in workshop_result.scalars().all()]
        
        # 4. Доступ через типы оборудования (EquipmentType)
        type_result = await db.execute(
            select(EquipmentTypeEngineerAccess.equipment_type_id).where(
                EquipmentTypeEngineerAccess.engineer_id == user.engineer_id,
                EquipmentTypeEngineerAccess.is_active == True
            )
        )
        type_ids = [str(id) for id in type_result.scalars().all()]
        
        # Получаем оборудование по иерархии
        equipment_query = select(Equipment.id)
        conditions = []
        
        # Если есть доступ к предприятию - получаем все оборудование этого предприятия
        if client_ids:
            # Получаем все цеха предприятий
            client_workshops_result = await db.execute(
                select(Workshop.id).where(
                    or_(*[Workshop.client_id == UUIDType(cid) for cid in client_ids])
                )
            )
            client_workshop_ids = [str(id) for id in client_workshops_result.scalars().all()]
            workshop_ids.extend(client_workshop_ids)
            
            # Получаем все филиалы предприятий
            client_branches_result = await db.execute(
                select(Branch.id).where(
                    or_(*[Branch.client_id == UUIDType(cid) for cid in client_ids])
                )
            )
            client_branch_ids = [str(id) for id in client_branches_result.scalars().all()]
            branch_ids.extend(client_branch_ids)
        
        # Если есть доступ к филиалам - получаем все оборудование филиалов
        if branch_ids:
            branch_workshops_result = await db.execute(
                select(Workshop.id).where(
                    or_(*[Workshop.branch_id == UUIDType(bid) for bid in branch_ids])
                )
            )
            branch_workshop_ids = [str(id) for id in branch_workshops_result.scalars().all()]
            workshop_ids.extend(branch_workshop_ids)
        
        # Если есть доступ к цехам - получаем оборудование этих цехов
        if workshop_ids:
            conditions.append(or_(*[Equipment.workshop_id == UUIDType(wid) for wid in workshop_ids]))
        
        # Если есть доступ к типам оборудования - получаем оборудование этих типов
        if type_ids:
            conditions.append(or_(*[Equipment.type_id == UUIDType(tid) for tid in type_ids]))
        
        if conditions:
            equipment_query = equipment_query.where(or_(*conditions))
            equipment_result = await db.execute(equipment_query)
            accessible_ids.update([str(id) for id in equipment_result.scalars().all()])
    
    # Добавляем прямое назначение на оборудование
    direct_result = await db.execute(
        select(UserEquipmentAccess.equipment_id).where(
            UserEquipmentAccess.user_id == user.id,
            UserEquipmentAccess.is_active == True
        )
    )
    accessible_ids.update([str(id) for id in direct_result.scalars().all()])
    
    return list(accessible_ids)

async def get_user_accessible_project_ids(db: AsyncSession, user: UserModel) -> List[str]:
    """Получить список ID проектов, к которым есть доступ"""
    if user.role in ["admin", "chief_operator", "operator"]:
        result = await db.execute(select(Project.id))
        return [str(proj_id) for proj_id in result.scalars().all()]
    else:
        result = await db.execute(
            select(UserProjectAccess.project_id).where(
                UserProjectAccess.user_id == user.id,
                UserProjectAccess.is_active == True
            )
        )
        return [str(proj_id) for proj_id in result.scalars().all()]



