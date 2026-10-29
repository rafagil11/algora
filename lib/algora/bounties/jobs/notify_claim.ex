defmodule Algora.Bounties.Jobs.NotifyClaim do
  @moduledoc """
  Background job to handle notifications for claim status changes.
  """
  use Oban.Worker, queue: :notifications

  alias Algora.Repo
  alias Algora.Bounties.Schemas.Claim
  alias Algora.Activities

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"claim_id" => claim_id, "event" => event}}) do
    claim = 
      Claim
      |> Repo.get(claim_id)
      |> Repo.preload([:user, :bounty, bounty: :user])

    case event do
      "rewarded" ->
        send_reward_notifications(claim)
      "approved" ->
        send_approval_notifications(claim)
      _ ->
        :ok
    end
  end

  def enqueue(claim_id, event) do
    %{"claim_id" => claim_id, "event" => to_string(event)}
    |> __MODULE__.new()
    |> Oban.insert()
  end

  defp send_reward_notifications(claim) do
    # Notify contributor that they've been paid
    Activities.create_activity(%{
      user_id: claim.user_id,
      type: :claim_paid,
      subject_id: claim.id,
      subject_type: "Claim",
      data: %{
        bounty_title: claim.bounty.title,
        amount: claim.amount
      }
    })
    
    # Logic for email/discord notifications would follow
    :ok
  end

  defp send_approval_notifications(claim) do
    # Notify sponsor that a claim is ready for reward after PR merge
    Activities.create_activity(%{
      user_id: claim.bounty.user_id,
      type: :claim_approved,
      subject_id: claim.id,
      subject_type: "Claim",
      data: %{
        contributor_handle: claim.user.handle,
        bounty_title: claim.bounty.title
      }
    })
    :ok
  end
end