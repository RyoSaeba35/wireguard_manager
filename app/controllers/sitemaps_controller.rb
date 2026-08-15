class SitemapsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  layout false

  def index
    @pages = [
      { loc: root_url(locale: nil),                 priority: "1.0", changefreq: "weekly"  },
      { loc: blog_url(locale: nil),                 priority: "0.9", changefreq: "weekly"  },
      { loc: blog_vpn_expats_url(locale: nil),      priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_logs_url(locale: nil),        priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_voyage_url(locale: nil),      priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_privee_url(locale: nil),      priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_vs_grands_url(locale: nil),   priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_teletravail_url(locale: nil), priority: "0.8", changefreq: "monthly" },
      { loc: blog_vpn_android_url(locale: nil),     priority: "0.8", changefreq: "monthly" },
      { loc: logging_url(locale: nil),              priority: "0.6", changefreq: "monthly" },
      { loc: privacy_url(locale: nil),              priority: "0.5", changefreq: "monthly" },
      { loc: terms_url(locale: nil),                priority: "0.5", changefreq: "monthly" },
    ]
    respond_to do |format|
      format.xml
    end
  end
end
