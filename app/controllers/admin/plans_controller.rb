# app/controllers/admin/plans_controller.rb
class Admin::PlansController < ApplicationController
  before_action :authenticate_user!
  before_action :verify_admin

  def create
    @plan = Plan.new(plan_params)

    if @plan.save
      render json: { success: true }
    else
      render json: { success: false, error: @plan.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    @plan = Plan.find(params[:id])

    if @plan.update(plan_params)
      render json: { success: true }
    else
      render json: { success: false, error: @plan.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  private

  def verify_admin
    redirect_to root_path, alert: "Access denied." unless current_user.admin?
  end

  def plan_params
    params.require(:plan).permit(:name, :price, :interval, :description, :active)
  end
end
