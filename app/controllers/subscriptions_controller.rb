# app/controllers/wireguard_clients_controller.rb
# class WireguardClientsController < ApplicationController
#   before_action :authenticate_user!

#   def new
#     @wireguard_client = current_user.wireguard_clients.new
#   end

#   # def create
#   #   # Use the service to create the WireGuard client and subscription
#   #   creator = WireguardClientCreator.new(current_user, wireguard_client_params[:name])
#   #   @wireguard_client = creator.call

#   #   if @wireguard_client.persisted?
#   #     redirect_to user_wireguard_client_path(current_user, @wireguard_client), notice: "WireGuard client created successfully."
#   #   else
#   #     render :new
#   #   end
#   # end

#   def create
#     # Generate a unique 6-character alphanumeric token
#     client_name = loop do
#       random_name = SecureRandom.alphanumeric(6).upcase
#       break random_name unless WireguardClient.exists?(name: random_name)
#     end

#     Rails.logger.info "Creating WireGuard client: #{client_name}"

#     # Use the service to create the WireGuard client and subscription
#     creator = WireguardClientCreator.new(current_user, client_name)
#     @wireguard_client = creator.call

#     if @wireguard_client.persisted?
#       redirect_to user_wireguard_client_path(current_user, @wireguard_client),
#                   notice: "WireGuard client created successfully."
#     else
#       render :new
#     end
#   end

#   # def show
#   #   @wireguard_client = current_user.wireguard_clients.find(params[:id])
#   # end

#   def show
#     @wireguard_client = WireguardClient.find(params[:id])
#   end


#   private

#   # def wireguard_client_params
#   #   params.require(:wireguard_client).permit(:name)
#   # end

#   def wireguard_client_params
#     params.require(:wireguard_client).permit(:other_attributes) # exclude :name
#   end
# end

# app/controllers/subscriptions_controller.rb
# app/controllers/subscriptions_controller.rb
class SubscriptionsController < ApplicationController
  before_action :authenticate_user!

  def new
    @subscription = current_user.subscriptions.new
  end

  def create
    # Generate a unique 6-character alphanumeric token for the subscription
    subscription_name = loop do
      random_name = SecureRandom.alphanumeric(6).upcase
      break random_name unless Subscription.exists?(name: random_name)
    end

    Rails.logger.info "Creating subscription: #{subscription_name}"

    # Use the service to create the subscription and wireguard client
    creator = SubscriptionCreator.new(current_user, subscription_name, subscription_params)
    @subscription = creator.call

    if @subscription.persisted?
      redirect_to user_subscription_path(current_user, @subscription),
                  notice: "Subscription and WireGuard client created successfully."
    else
      render :new
    end
  end

  def show
    @subscription = current_user.subscriptions.find(params[:id])
    @wireguard_clients = @subscription.wireguard_clients
    @wireguard_client = @wireguard_clients.first if @wireguard_clients.any?
  end

  private

  def subscription_params
    params.require(:subscription).permit(:plan, :price)
  end
end
