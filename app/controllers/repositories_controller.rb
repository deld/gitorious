#--
#   Copyright (C) 2007-2009 Johan Sørensen <johan@johansorensen.com>
#   Copyright (C) 2008 David A. Cuadrado <krawek@gmail.com>
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++

class RepositoriesController < ApplicationController
  before_filter :login_required, :except => [:index, :show, :writable_by]
  before_filter :find_repository_owner
  before_filter :require_adminship, :only => [:edit, :update]
  before_filter :require_user_has_ssh_keys, :only => [:clone, :create_clone]
  session :off, :only => [:writable_by]
  skip_before_filter :public_and_logged_in, :only => [:writable_by]
  
  def index
    @repositories = @owner.repositories.find(:all, :include => [:user, :events, :project])
  end
    
  def show
    @repository = Repository.all_by_owner(@owner).find_by_name!(params[:id])
    @events = @repository.events.paginate(:all, :page => params[:page], 
      :order => "created_at desc")
    
    @atom_auto_discovery_url = formatted_project_repository_path(@owner, @repository, :atom)
    respond_to do |format|
      format.html
      format.xml  { render :xml => @repository }
      format.atom {  }
    end
  end
  
  def new
    @repository = @owner.repositories.new
  end
  
  def create
    @repository = @owner.repositories.new(params[:repository])
    @repository.user = current_user
    
    if @repository.save
      flash[:success] = I18n.t("repositories_controller.create_success")
      redirect_to [@owner, @repository]
    else
      render :action => "new"
    end
  end
  
  def clone
    @repository_to_clone = @owner.repositories.find_by_name!(params[:id])
    unless @repository_to_clone.has_commits?
      flash[:error] = I18n.t "repositories_controller.new_clone_error"
      redirect_to project_repository_path(@owner, @repository_to_clone)
      return
    end
    @repository = Repository.new_by_cloning(@repository_to_clone, current_user.login)
  end
  
  def create_clone
    @repository_to_clone = @owner.repositories.find_by_name!(params[:id])
    unless @repository_to_clone.has_commits?
      target_path = project_repository_path(@owner, @repository_to_clone)
      respond_to do |format|
        format.html do
          flash[:error] = I18n.t "repositories_controller.create_clone_error"
          redirect_to target_path
        end
        format.xml do 
          render :text => I18n.t("repositories_controller.create_clone_error"), 
            :location => target_path, :status => :unprocessable_entity
        end
      end
      return
    end
    @repository = Repository.new_by_cloning(@repository_to_clone)
    @repository.name = params[:repository][:name]
    @repository.user = current_user
    @repository.owner = case params[:repository][:owner_type]
    when "User"
      current_user
    when "Group"
      current_user.groups.find(params[:repository][:owner_id])
    end
    
    respond_to do |format|
      if @repository.save
        @owner.create_event(Action::CLONE_REPOSITORY, @repository, current_user, @repository_to_clone.id)
        
        location = project_repository_path(@owner, @repository)
        format.html { redirect_to location }
        format.xml  { render :xml => @repository, :status => :created, :location => location }        
      else
        format.html { render :action => "clone" }
        format.xml  { render :xml => @repository.errors, :status => :unprocessable_entity }
      end
    end
  end
  
  # Used internally to check write permissions by gitorious
  def writable_by
    @repository = @owner.repositories.find_by_name!(params[:id])
    user = User.find_by_login(params[:username])
    if user && user.can_write_to?(@repository)
      render :text => "true"
    else
      render :text => "false"
    end
  end
  
  def confirm_delete
    @repository = @owner.repositories.find_by_name!(params[:id])
  end
  
  def destroy
    @repository = @owner.repositories.find_by_name!(params[:id])
    if @repository.can_be_deleted_by?(current_user)
      repo_name = @repository.name
      flash[:notice] = I18n.t "repositories_controller.destroy_notice"
      @repository.destroy
      @owner.create_event(Action::DELETE_REPOSITORY, @owner, current_user, repo_name)
    else
      flash[:error] = I18n.t "repositories_controller.destroy_error"
    end
    redirect_to project_path(@owner)
  end
  
  private    
    def require_adminship
      unless @owner.admin?(current_user)
        respond_to do |format|
          flash[:error] = I18n.t "repositories_controller.adminship_error"
          format.html { redirect_to(project_path(@owner)) }
          format.xml  { render :text => I18n.t( "repositories_controller.adminship_error"), :status => :forbidden }
        end
        return
      end
    end
end
