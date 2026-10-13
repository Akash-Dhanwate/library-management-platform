class User:
    def __init__(self, user_id, name, email, role="Student"):
        self.user_id = user_id
        self.name = name
        self.email = email
        self.role = role
        self.active_loans = 0
