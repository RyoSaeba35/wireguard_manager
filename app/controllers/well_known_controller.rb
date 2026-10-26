# app/controllers/well_known_controller.rb
#
# GET /.well-known/assetlinks.json
# Lets Android verify that the Vulcain app may open links on this domain
# (App Links). Confirmation email links then open the app on phones where it
# is installed, and the website everywhere else.
#
# ENV ANDROID_CERT_SHA256 = comma-separated SHA-256 fingerprints, e.g.
#   "AB:CD:...:EF,12:34:...:56"
# Put both the Play App Signing key (Play Console > App integrity) and your
# upload key (for builds installed with `flutter run --release`).
class WellKnownController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  ANDROID_PACKAGE = "com.vulcainvpn.app".freeze

  def assetlinks
    fingerprints = ENV.fetch("ANDROID_CERT_SHA256", "")
                      .split(",").map(&:strip).reject(&:blank?).map(&:upcase)

    expires_in 1.hour, public: true

    render json: [
      {
        relation: ["delegate_permission/common.handle_all_urls"],
        target: {
          namespace: "android_app",
          package_name: ANDROID_PACKAGE,
          sha256_cert_fingerprints: fingerprints
        }
      }
    ]
  end
end
