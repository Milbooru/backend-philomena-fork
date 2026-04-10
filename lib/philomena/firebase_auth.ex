defmodule Philomena.FirebaseAuth do
  @moduledoc """
  Verifies Firebase ID tokens (RS256 JWTs) against Firebase's public JWKS.

  Keys are cached in an Agent and refreshed every 5 minutes. On a failed
  refresh the previous key set is kept so in-flight requests survive a
  transient network hiccup.
  """

  use Agent

  @jwks_url "https://www.googleapis.com/robot/v1/metadata/jwk/securetoken@system.gserviceaccount.com"
  @cache_ttl_seconds 300

  def start_link(_opts) do
    Agent.start_link(fn -> {[], 0} end, name: __MODULE__)
  end

  @doc """
  Verify a Firebase ID token string.

  Returns `{:ok, claims}` where `claims` is a plain map with at minimum:
    - `"sub"` — the Firebase UID
    - `"email"` — the user's email
    - `"email_verified"` — boolean
    - `"name"` — display name, if set (may be absent)

  Returns `{:error, reason}` on any failure.
  """
  def verify_id_token(id_token) when is_binary(id_token) do
    project_id = Application.fetch_env!(:philomena, :firebase_project_id)

    with {:ok, keys} <- get_keys(),
         {:ok, claims} <- verify_signature(id_token, keys),
         :ok <- validate_claims(claims, project_id) do
      {:ok, claims}
    end
  end

  # ---------------------------------------------------------------------------
  # Key cache
  # ---------------------------------------------------------------------------

  defp get_keys do
    now = System.system_time(:second)
    {keys, fetched_at} = Agent.get(__MODULE__, & &1)

    if keys != [] and now - fetched_at < @cache_ttl_seconds do
      {:ok, keys}
    else
      case fetch_and_cache(now) do
        {:ok, _} = ok -> ok
        # On fetch failure keep stale keys if we have them
        {:error, _} = err -> if keys != [], do: {:ok, keys}, else: err
      end
    end
  end

  defp fetch_and_cache(now) do
    case Req.get(@jwks_url) do
      {:ok, %{status: 200, body: %{"keys" => keys}}} ->
        Agent.update(__MODULE__, fn _ -> {keys, now} end)
        {:ok, keys}

      {:ok, %{status: status}} ->
        {:error, {:jwks_http_error, status}}

      {:error, reason} ->
        {:error, {:jwks_request_failed, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Signature verification — try each cached key (handles key rotation)
  # ---------------------------------------------------------------------------

  defp verify_signature(token, keys) do
    Enum.find_value(keys, {:error, :invalid_signature}, fn jwk_map ->
      try do
        jwk = JOSE.JWK.from_map(jwk_map)

        case JOSE.JWT.verify_strict(jwk, ["RS256"], token) do
          {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
          _ -> nil
        end
      rescue
        _ -> nil
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Claims validation
  # ---------------------------------------------------------------------------

  defp validate_claims(claims, project_id) do
    now = System.system_time(:second)

    cond do
      claims["aud"] != project_id ->
        {:error, :invalid_audience}

      claims["iss"] != "https://securetoken.google.com/#{project_id}" ->
        {:error, :invalid_issuer}

      not is_integer(claims["exp"]) or claims["exp"] <= now ->
        {:error, :token_expired}

      not is_integer(claims["iat"]) or claims["iat"] > now + 300 ->
        {:error, :token_not_yet_valid}

      true ->
        :ok
    end
  end
end
