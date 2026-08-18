"""Legacy wire enums retained for compatibility response schemas.

There is intentionally no TeamTask ORM model.  Task persistence lives only in
``Todo`` (the existing Task table) and ``TodoAssignment``.
"""
from enum import Enum


class TeamTaskStatus(str, Enum):
    ACTIVE = "ACTIVE"
    COMPLETED = "COMPLETED"
    CANCELLED = "CANCELLED"


class TeamTaskAssignmentStatus(str, Enum):
    TODO = "TODO"
    DONE = "DONE"
