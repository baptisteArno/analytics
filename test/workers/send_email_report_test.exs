defmodule Plausible.Workers.SendEmailReportTest do
  import Plausible.TestUtils
  use Plausible.DataCase
  use Bamboo.Test
  alias Plausible.Workers.SendEmailReport
  alias Timex.Timezone

  defp perform(args) do
    SendEmailReport.new(args) |> Oban.insert!()
    Oban.drain_queue(:send_email_reports)
  end

  describe "weekly reports" do
    test "sends weekly report to all recipients" do
      site = insert(:site, domain: "test-site.com", timezone: "US/Eastern")
      insert(:weekly_report, site: site, recipients: ["user@email.com", "user2@email.com"])

      perform(%{"site_id" => site.id, "interval" => "weekly"})

      assert_email_delivered_with(
        subject: "Weekly report for #{site.domain}",
        to: [nil: "user@email.com"]
      )

      assert_email_delivered_with(
        subject: "Weekly report for #{site.domain}",
        to: [nil: "user2@email.com"]
      )
    end

    test "calculates timezone correctly" do
      site = insert(:site, timezone: "US/Eastern")
      insert(:weekly_report, site: site, recipients: ["user@email.com"])

      now = Timex.now(site.timezone)
      last_monday = Timex.shift(now, weeks: -1) |> Timex.beginning_of_week()
      last_sunday = Timex.shift(now, weeks: -1) |> Timex.end_of_week()
      sunday_before_last = Timex.shift(last_monday, minutes: -1)
      this_monday = Timex.beginning_of_week(now)

      create_pageviews([
        # Sunday before last, not counted
        %{domain: site.domain, timestamp: Timezone.convert(sunday_before_last, "UTC")},
        # Sunday before last, not counted
        %{domain: site.domain, timestamp: Timezone.convert(sunday_before_last, "UTC")},
        # Last monday, counted
        %{domain: site.domain, timestamp: Timezone.convert(last_monday, "UTC")},
        # Last sunday, counted
        %{domain: site.domain, timestamp: Timezone.convert(last_sunday, "UTC")},
        # This monday, not counted
        %{domain: site.domain, timestamp: Timezone.convert(this_monday, "UTC")},
        # This monday, not counted
        %{domain: site.domain, timestamp: Timezone.convert(this_monday, "UTC")}
      ])

      perform(%{"site_id" => site.id, "interval" => "weekly"})

      assert_delivered_email_matches(%{
        to: [nil: "user@email.com"],
        html_body: html_body
      })

      # Should find 2 visiors
      assert html_body =~
               ~s(<span id="visitors" style="line-height: 24px; font-size: 20px;">2</span>)
    end
  end

  describe "monthly_reports" do
    test "sends monthly report to all recipients" do
      site = insert(:site, domain: "test-site.com", timezone: "US/Eastern")
      insert(:monthly_report, site: site, recipients: ["user@email.com", "user2@email.com"])

      last_month =
        Timex.now(site.timezone)
        |> Timex.shift(months: -1)
        |> Timex.beginning_of_month()
        |> Timex.format!("{Mfull}")

      perform(%{"site_id" => site.id, "interval" => "monthly"})

      assert_email_delivered_with(
        subject: "#{last_month} report for #{site.domain}",
        to: [nil: "user@email.com"]
      )

      assert_email_delivered_with(
        subject: "#{last_month} report for #{site.domain}",
        to: [nil: "user2@email.com"]
      )
    end
  end
end
