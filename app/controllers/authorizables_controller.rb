class AuthorizablesController < ApplicationController
  def show
    @object = model_class.find(params[:id])
  end

  def update
    @object = model_class.find(params[:id])

    user_access_levels = (params[:user_permissions] || []).each_with_object({}) do |permission, result|
      result[permission[:user][:id]] = permission[:level]
    end
    @object.set_access_levels(User, user_access_levels)

    group_access_levels = (params[:group_permissions] || []).each_with_object({}) do |permission, result|
      result[permission[:group][:id]] = permission[:level]
    end
    @object.set_access_levels(Group, group_access_levels)

    render :show
  end

  def user_and_group_search
    @users, @groups = if params[:query].present?

      [User.for_query(params[:query]), Group.for_query(params[:query])]
    else
      [[], []]
    end
  end
end