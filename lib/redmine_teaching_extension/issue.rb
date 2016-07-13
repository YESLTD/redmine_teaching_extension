require_dependency 'issue'

class Issue

  has_and_belongs_to_many :projects

  alias_method :issue_visible?, :visible? # alias_method(new_name, old_name) -> self. Makes <i>new_name</i> a new copy of the method <i>old_name</i>.
  alias_method :issue_notified_users, :notified_users

  self.singleton_class.send(:alias_method, :issue_visible_condition, :visible_condition)


  # Comprobar si tanto los usuarios del sistema como el usuario actual, tienen permisos suficientes para ver la Issue,
  # y llevar a cabo la propagación de la misma entre alumnos de la asignatura:
  def visible?(usr = nil)
    issue_visible?(usr) || other_project_visible(usr)
  end

  # Usuarios de los subproyectos del proyecto principal, al que se le puede asignar la Issue
=begin
  def assignable_users_subprojects
    subprojects = Project.where(:parent_id => project)
    subproject_members = []
    subprojects.each do |subproject|
      subproject_members += Principal.member_of(subproject)
    end
    users = subproject_members
    users << author if author
    users << assigned_to if assigned_to
    users.uniq.sort
  end
=end

  # Copies attributes from another issue, arg can be an id or an Issue
=begin
  def copy_from_subprojects(arg, options={})
    issue = arg.is_a?(Issue) ? arg : Issue.visible.find(arg)
    self.attributes = issue.attributes.dup.except("id", "root_id", "parent_id", "lft", "rgt", "created_on", "updated_on")
    self.custom_field_values = issue.custom_field_values.inject({}) {|h,v| h[v.custom_field_id] = v.value; h}
    self.status = issue.status
    self.author = User.current
    unless options[:attachments] == false
      self.attachments = issue.attachments.map do |attachement|
        attachement.copyy(:container => self)
      end
    end
    @copied_from = issue
    @copy_options = options
    self
  end

  # Returns an unsaved copy of the issue
  def copyy(attributes=nil, copy_options={})
    copy = self.class.new.copy_from_subprojects(self, copy_options)
    copy.attributes = attributes if attributes
    copy
  end
=end

  # Devuelve true si el usuario del sistema ó usuario actual tiene permiso para ver la issue
  # (nueva implementación del método 'visible?' existente en models/issue.rb)
  def other_project_visible?(usr = nil)
    other_projects = self.projects - [self.project]
    other_projects_visibility = false

    other_projects.each do |project|
      if other_projects_visibility == false
        other_projects_visibility = (usr || User.current).allowed_to?(:view_issues, project) do |role, user|
          if user.logged?
            case role.issues_visibility
              when 'all'
                true
              when 'default'
                !self.is_private? || (self.author == user || user.is_or_belongs_to?(assigned_to))
              when 'own'
                self.author == user || user.is_or_belongs_to?(assigned_to)
              else
                false
            end
          else
            !self.is_private?
          end
        end
      else
        break
      end
    end
    other_projects_visibility
  end

  # Función que devuelve una consulta SQL usada para encontrar todas las issues visibles por el usuario especificado:
  def self.visible_condition(user, options={})
    statement_by_role = {}
    user.projects_by_role.each do |role, projects|
      if role.allowed_to?(:view_issues) && projects.any?
        statement_by_role[role] = "project_id IN (#{projects.collect(&:id).join(',')})"
      end
    end
    authorized_projects = statement_by_role.values.join(' OR ')

    if authorized_projects.present?
      "(#{issue_visible_condition(user, options)} OR #{Issue.table_name}.id IN (SELECT issue_id FROM issues_projects WHERE (#{authorized_projects}) ))"
    else
      issue_visible_condition(user, options)
    end
  end

  # Función que devuelve el conjunto de usuarios del sistema que deben ser notificados de una issue asignada:
  def notified_users
    notified = issue_notified_users
    notified_from_other_projects = notified_users_from_other_projects - notified
    notified_from_other_projects.reject { |user| !other_project_visible?(user) } # Eliminar usuarios que no pueden visualizar la issue
    notified_from_other_projects | notified
  end

  def notified_users_from_other_projects
    notified = []
    other_projects = self.projects - [self.project]
    other_projects.each do |pr|
      notified = notified | pr.notified_users
    end
    notified
  end

end