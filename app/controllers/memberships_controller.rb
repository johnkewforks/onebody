class MembershipsController < ApplicationController
  skip_before_action :authenticate_user, only: %w(show update)
  before_action :authenticate_user_with_code_or_session, only: %w(show update)

  load_parent :group

  before_action :authorize_group_for_read,   only: :index
  before_action :authorize_group_for_update, only: :batch

  def show
    # allow email links to work (since they will be GET requests)
    if params[:email]
      update
    else
      fail ActionController::UnknownAction, t('No_action_to_show')
    end
  end

  def index
    @memberships = @group.memberships.includes(:person).paginate(page: params[:page], per_page: 100)
    if params[:birthdays]
      @memberships = @memberships.order_by_birthday
    else
      @memberships = @memberships.order_by_name
    end
    @requests = @group.membership_requests
  end

  # join group
  def create
    @person = Person.find(params[:id])
    if @logged_in.can_create?(@group.memberships.new)
      @group.memberships.create(person: @person)
    elsif me?
      @group.membership_requests.create(person: @person)
      flash[:warning] = t('groups.join.request_sent')
    end
    redirect_to :back
  end

  def update
    if params[:email]
      update_email
    elsif params[:promote] && @logged_in.can_update?(@group)
      update_admin
    else
      render text: t('not_authorized'), layout: true, status: 401
    end
  end

  def update_email
    @person = Person.find(params[:id])
    if can_update_email?
      @get_email = params[:email] == 'on'
      @group.set_options_for @person, get_email: @get_email
      respond_to do |format|
        format.html do
          flash[:notice] = t('groups.email_settings_changed')
          redirect_to :back
        end
        format.js
      end
    else
      render text: t('not_authorized'), layout: true, status: 401
    end
  end

  def update_admin
    @membership = @group.memberships.find(params[:id])
    @membership.update_attribute(:admin, params[:promote] == 'true')
    flash[:notice] = t('groups.user_settings_saved')
    redirect_to :back
  end

  # leave group
  def destroy
    @membership = @group.memberships.where(person_id: params[:id]).first!
    if @logged_in.can_delete?(@membership)
      if @membership.only_admin?
        flash[:warning] = t('groups.last_admin_remove', name: @membership.person.name)
      else
        @membership.destroy
      end
    end
    respond_to do |format|
      format.html { redirect_to :back }
      format.js
    end
  end

  def batch
    batch = MembershipBatch.new(@group, params[:ids])
    if request.post?
      batch.delete_requests
      @added = batch.create unless params[:commit] == 'ignore'
    elsif request.delete?
      batch.delete
    end
    @added ||= []
    respond_to do |format|
      format.js
      format.html { redirect_to :back }
    end
  end

  private

  def can_update_email?
    @logged_in.can_update?(@group) || @logged_in.can_update?(@person)
  end

  def authorize_group_for_read
    return if @logged_in.can_read?(@group)
    render text: t('not_authorized'), layout: true, status: :unauthorized
    false
  end

  def authorize_group_for_update
    return if @logged_in.can_update?(@group)
    render text: t('not_authorized'), layout: true, status: :unauthorized
    false
  end
end
