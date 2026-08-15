class SitemapsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  layout false

  def index
    @pages = [
      { loc: root_url,                   priority: "1.0", changefreq: "weekly"  },
      { loc: blog_url,                   priority: "0.9", changefreq: "weekly"  },
      { loc: blog_vpn_expats_url,        priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_logs_url,          priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_voyage_url,        priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_privee_url,        priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_vs_grands_url,     priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_teletravail_url,   priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_android_url,       priority: "0.8", changefreq: "monthly" },
      { loc: logging_url,                priority: "0.6", changefreq: "monthly" },
      { loc: privacy_url,                priority: "0.5", changefreq: "monthly" },
      { loc: terms_url,                  priority: "0.5", changefreq: "monthly" },
    ]
    respond_to do |format|
      format.xml
    end
  end
end
