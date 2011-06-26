class UserController < ApplicationController
  layout :choose_layout
  before_filter :login_required, :except => [:forgot_password, :login, :set_new_password, :reset_password]
  before_filter :only_admin_allowed, :only => [:edit, :create, :index, :edit_privilege]
#  filter_access_to :edit_privilege
  def choose_layout
    return 'login' if action_name == 'login' or action_name == 'set_new_password'
    return 'forgotpw' if action_name == 'forgot_password'
    return 'dashboard' if action_name == 'dashboard'
    'application'
  end
  
  def all
    @users = User.all
  end
  
  def list_user
    if params[:user_type] == 'Administrador'
      @users = User.find(:all, :conditions => {:admin => true}, :order => 'first_name ASC')
      render(:update) do |page|
        page.replace_html 'users', :partial=> 'users'
        page.replace_html 'employee_user', :text => ''
        page.replace_html 'student_user', :text => ''
      end
    elsif params[:user_type] == 'Empregado'
      render(:update) do |page|
        hr = Configuration.find_by_config_value("HR")
        unless hr.nil?
          page.replace_html 'employee_user', :partial=> 'employee_user'
          page.replace_html 'users', :text => ''
          page.replace_html 'student_user', :text => ''
        else
          @users = User.find_all_by_employee(1)
          page.replace_html 'users', :partial=> 'users'
          page.replace_html 'employee_user', :text => ''
          page.replace_html 'student_user', :text => ''
        end
      end
    elsif params[:user_type] == 'Aluno'
      render(:update) do |page|
        page.replace_html 'student_user', :partial=> 'student_user'
        page.replace_html 'users', :text => ''
        page.replace_html 'employee_user', :text => ''
      end
    elsif params[:user_type] == ''
      @users = ""
      render(:update) do |page|
        page.replace_html 'users', :partial=> 'users'
        page.replace_html 'employee_user', :text => ''
        page.replace_html 'student_user', :text => ''
      end
    end
  end

  def list_employee_user
    emp_dept = params[:dept_id]
    @employee = Employee.find_all_by_employee_department_id(emp_dept, :order =>'first_name ASC')
    @users = @employee.collect { |employee| employee.user}
    @users.delete(nil)
    render(:update) {|page| page.replace_html 'users', :partial=> 'users'}
  end

  def list_student_user
    batch = params[:batch_id]
    @student = Student.find_all_by_batch_id(batch, :conditions => { :is_active => true },:order =>'first_name ASC')
    @users = @student.collect { |student| student.user}
    @users.delete(nil)
    render(:update) {|page| page.replace_html 'users', :partial=> 'users'}
  end

  def change_password
    
    if request.post?
      @user = current_user
      if User.authenticate?(@user.username, params[:user][:old_password])
        if params[:user][:new_password] == params[:user][:confirm_password]
          @user.password = params[:user][:new_password]
          @user.update_attributes(:password => @user.password,
            :role => @user.role_name
          )
          flash[:notice] = 'Senha alterada com sucesso.'
          redirect_to :action => 'dashboard'
        else
          flash[:warn_notice] = '<p>A confirmação de senha falhou. Por favor, tente novamente.</p>'
        end
      else
        flash[:warn_notice] = '<p>A senha antiga que você inseriu é incorreta. Por favor digite a senha válida.</p>'
      end
    end
  end

  def user_change_password
    user = User.find_by_username(params[:id])

    if request.post?
      if params[:user][:new_password]=='' and params[:user][:confirm_password]==''
        flash[:warn_notice]= "<p>Campos de senha não pode estar em branco!</p>"
      else
        if params[:user][:new_password] == params[:user][:confirm_password]
          user.password = params[:user][:new_password]
          user.update_attributes(:password => user.password,
            :role => user.role_name
          )
          flash[:notice]= "Senha foi atualizada com sucesso!"
          redirect_to :action=>"edit", :id=>user.username
        else
          flash[:warn_notice] = '<p>A confirmação de senha falhou. Por favor, tente novamente.</p>'
        end
      end

      
    end
  end

  def create
    @config = Configuration.available_modules

    @user = User.new(params[:user])
    if request.post?
      if @user.save
        if @config.include?('HR')
          @employee = Employee.new
          @employee.first_name =  @user.first_name
          @employee.last_name =  @user.last_name
          @employee.employee_number =  @user.username
          @employee.employee_number =  @user.username
          @employee.employee_category_id =  1
          @employee.employee_position_id =  1
          @employee.employee_department_id =  1
          @employee.employee_grade_id =  1
          @employee.date_of_birth =  Date.today - 20.year
          @employee.joining_date =  Date.today - 5.year
          @employee.save
        end
        flash[:notice] = 'Conta de usuário criada!'
        redirect_to :controller => 'user', :action => 'edit', :id => @user.username
      else
        flash[:notice] = 'Conta de usuário não foi criada!'
      end
    end
  end

  def delete
    @user = User.find_by_username(params[:id]).destroy
    flash[:notice] = 'Conta de usuário excluída!'
    redirect_to :controller => 'user'
  end

  def dashboard
    @user = current_user
    #@reminders = @users.check_reminders
    @config = Configuration.available_modules
    @employee = Employee.find_by_employee_number(@user.username)
    @employee ||= Employee.first if current_user.admin?
    @student = Student.find_by_admission_no(@user.username)
  end

  def edit
    @user = User.find_by_username(params[:id])
    @current_user = current_user
    if request.post? and @user.update_attributes(params[:user])
      flash[:notice] = 'Conta de usuário atualizada!'
      redirect_to :controller => 'user', :action => 'profile', :id => @user.username
    end
  end

  def forgot_password
#    flash[:notice]="You do not have permission to access forgot password!"
#    redirect_to :action=>"login"
  
    if request.post? and params[:reset_password]
      if user = User.find_by_email(params[:reset_password][:email])
        user.reset_password_code = Digest::SHA1.hexdigest( "#{user.email}#{Time.now.to_s.split(//).sort_by {rand}.join}" )
        user.reset_password_code_until = 1.day.from_now
        user.role = user.role_name
        user.save(false)
        UserNotifier.deliver_forgot_password(user)
        flash[:notice] = "Link de redefinição de senha enviado por email para #{user.email}"
        redirect_to :action => "index"
      else
        flash[:notice] = "Nenhum usuário cadastrado com endereço de email #{params[:reset_password][:email]}"
      end
    end
  end

  def login
    @institute = Configuration.find_by_config_key("LogoName")
    if request.post? and params[:user]
      @user = User.new(params[:user])
      user = User.find_by_username @user.username
      if user and User.authenticate?(@user.username, @user.password)
        session[:user_id] = user.id
        flash[:notice] = "Bem-vindo, #{user.first_name} #{user.last_name}!"
        redirect_to :controller => 'user', :action => 'dashboard'
      else
        flash[:notice] = 'Nome de usuário ou senha inválida'
      end
    end
  end

  def logout
    session[:user_id] = nil
    flash[:notice] = 'Sair'
    redirect_to :controller => 'user', :action => 'login'
  end

  def profile
    @config = Configuration.available_modules
    @current_user = current_user
    @username = @current_user.username if session[:user_id]
    @user = User.find_by_username(params[:id])
    @employee = Employee.find_by_employee_number(@user.username)
    @student = Student.find_by_admission_no(@user.username)
    if @user.nil?
      flash[:notice] = 'Perfil de usuário não encontrado.'
      redirect_to :action => 'dashboard'
    end
  end

  def reset_password
    user = User.find_by_reset_password_code(params[:id])
    if user
      if user.reset_password_code_until > Time.now
        redirect_to :action => 'set_new_password', :id => user.reset_password_code
      else
        flash[:notice] = 'Tempo de redefinição expirado'
        redirect_to :action => 'index'
      end
    else
      flash[:notice]= 'Link de redefinição inválido'
      redirect_to :action => 'index'
    end
  end

  def search_user_ajax
    unless params[:query].nil? or params[:query].empty? or params[:query] == ' '
      @user = User.first_name_or_last_name_or_username_like_any params[:query].split
    else
      @user = ''
    end
    render :layout => false
  end

  def set_new_password
    if request.post?
      user = User.find_by_reset_password_code(params[:id])
      if user
        if params[:set_new_password][:new_password] === params[:set_new_password][:confirm_password]
          user.password = params[:set_new_password][:new_password]
          user.update_attributes(:password => user.password, :reset_password_code => nil, :reset_password_code_until => nil, :role => user.role_name)
          #User.update(user.id, :password => params[:set_new_password][:new_password],
           # :reset_password_code => nil, :reset_password_code_until => nil)
          flash[:notice] = 'Senha redefinida com sucesso. Use a nova senha para entrar.'
          redirect_to :action => 'index'
        else
          flash[:notice] = 'A confirmação de senha falhou. Por favor, digite a senha novamente.'
          redirect_to :action => 'set_new_password', :id => user.reset_password_code
        end
      else
        flash[:notice] = 'Você seguiu um link inválido. Por favor, tente novamente.'
        redirect_to :action => 'index'
      end
    end
  end

  def edit_privilege
    @privileges = Privilege.find(:all)
    @user = User.find_by_username(params[:id])
    if request.post?
      new_privileges = params[:user][:privilege_ids] if params[:user]
      new_privileges ||= []
      @user.privileges = Privilege.find_all_by_id(new_privileges)

      flash[:notice] = 'Papel atualizado.'
      redirect_to :action => 'profile',:id => @user.username
    end
  end

  def header_link
   @user = current_user
    #@reminders = @users.check_reminders
    @config = Configuration.available_modules
    @employee = Employee.find_by_employee_number(@user.username)
    @employee ||= Employee.first if current_user.admin?
    @student = Student.find_by_admission_no(@user.username)
    render :partial=>'header_link'
end
end

