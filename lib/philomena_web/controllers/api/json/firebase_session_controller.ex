defmodule PhilomenaWeb.Api.Json.FirebaseSessionController do
  @moduledoc """
  Accepts a Firebase ID token and returns the user's Philomena API token.

  Flow:
    1. Client sends POST /api/v1/json/firebase/session with {"firebase_token": "..."}
    2. Token is verified against Firebase's JWKS (RS256)
    3. email_verified must be true
    4. Philomena user is found by firebase_uid, or linked by email, or auto-created
    5. Returns {"authentication_token": "...", "id": ..., "name": "..."}

  The returned authentication_token is the per-user ?key= value for all
  subsequent Philomena API calls.
  """

  use PhilomenaWeb, :controller

  alias Philomena.{Users, FirebaseAuth}

  def create(conn, %{"firebase_token" => token} = params) do
    case FirebaseAuth.verify_id_token(token) do
      {:ok, claims} ->
        handle_verified(conn, claims, params)

      {:error, reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid Firebase token", detail: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "firebase_token is required"})
  end

  # ---------------------------------------------------------------------------
  # Verified-token handlers
  # ---------------------------------------------------------------------------

  defp handle_verified(
         conn,
         %{"sub" => uid, "email" => email, "email_verified" => true} = claims,
         params
       ) do
    user =
      Users.get_user_by_firebase_uid(uid) ||
        find_and_link_by_email(email, uid)

    case user do
      nil ->
        register_new_user(conn, uid, email, claims, params)

      %{} = found ->
        json(conn, %{
          authentication_token: found.authentication_token,
          id: found.id,
          name: found.name
        })
    end
  end

  defp handle_verified(conn, _claims, _params) do
    conn
    |> put_status(:forbidden)
    |> json(%{error: "Email not verified. Please verify your email address before signing in."})
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp find_and_link_by_email(email, uid) do
    case Users.get_user_by_email(email) do
      nil ->
        nil

      user ->
        case Users.link_firebase_uid(user, uid) do
          {:ok, updated} -> updated
          # Link failed (race condition or already set) — return as-is
          {:error, _} -> user
        end
    end
  end

  defp register_new_user(conn, uid, email, claims, params) do
    name = Map.get(params, "name") || claims["name"] || name_from_email(email)

    case Users.register_user_from_firebase(%{
           "name" => name,
           "email" => email,
           "firebase_uid" => uid
         }) do
      {:ok, new_user} ->
        conn
        |> put_status(:created)
        |> json(%{
          authentication_token: new_user.authentication_token,
          id: new_user.id,
          name: new_user.name
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Registration failed", details: format_errors(changeset)})
    end
  end

  defp name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 50)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
