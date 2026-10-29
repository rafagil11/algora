defmodule Algora.Bounties do
  @moduledoc """
  Context module for managing bounties and claims.
  """

  import Ecto.Query, warn: false
  alias Algora.Repo
  alias Algora.Bounties.Schemas.{Bounty, Claim}
  alias Algora.Accounts.Schemas.User

  @doc """
  Checks if a user can reward a specific claim.
  Sponsors should be able to reward approved claims even if the bounty is closed (e.g. after a PR merge).
  """
  def can_reward_claim?(%Claim{} = claim, %User{} = user) do
    claim = Repo.preload(claim, [:bounty])
    bounty = claim.bounty

    is_sponsor = bounty.user_id == user.id or is_org_admin?(bounty, user)
    
    # A claim can be rewarded if it's approved, regardless of whether the bounty is open or closed.
    # Often, merging the PR closes the bounty, but the reward happens immediately after.
    is_sponsor && claim.status == :approved
  end

  @doc """
  Processes the reward for a claim, transitioning it from approved to paid/rewarded.
  """
  def reward_claim(%Claim{} = claim, params \\ %{}) do
    Repo.transaction(fn ->
      claim = Repo.preload(claim, [:bounty, :user])
      
      case claim.status do
        :approved ->
          claim
          |> Claim.changeset(Map.put(params, "status", :paid))
          |> Repo.update!()
          |> maybe_close_bounty()
          |> notify_contributor_of_reward()

        :paid ->
          {:error, :already_paid}

        _ ->
          {:error, :invalid_status}
      end
    end)
  end

  defp is_org_admin?(%Bounty{organization_id: nil}, _user), do: false
  defp is_org_admin?(%Bounty{organization_id: org_id}, user) do
    # Logic to check if user is admin of the organization
    Algora.Accounts.is_admin?(user, org_id)
  end

  defp maybe_close_bounty(%Claim{bounty: bounty} = claim) do
    # If all approved claims are now paid and the bounty is still open, close it.
    # If it's already closed/merged, this is a no-op.
    if bounty.status == :open do
      bounty
      |> Bounty.changeset(%{status: :closed, closed_at: DateTime.utc_now()})
      |> Repo.update!()
    end
    claim
  end

  defp notify_contributor_of_reward(claim) do
    # Trigger notification job
    Algora.Bounties.Jobs.NotifyClaim.enqueue(claim.id, :rewarded)
    claim
  end
end