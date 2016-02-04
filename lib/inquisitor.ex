defmodule Inquisitor do
  @moduledoc """
  Composable query builder for Ecto.

  Inquisitor provides functionality to build a powerful query builder
  from a very simple pattern.

      defmodule App.PostController do
        use Inquisitor, with: App.Post
      end

  This will inject the necessary code into the `App.PostController`
  module. The function name depends upon the model name. In this case
  the function injected will be called `build_post_query/1`. If the
  model name was `App.FooBarBaz` the corresponding function name would
  be `build_foo_bar_baz/1`. The last segment of the module name is
  always used, ignoring all other namespacing. A model named
  `Foo.Bar.Baz` would inject a function named `build_baz_query/1`.

  The builder function expects a flat map of key/value pairs to be
  passed in. Typically this might be captured from an incoming request.

  `[GET] /posts?foo=hello&bar=world` may result in a params map of
  `%{"foo" => "hello", "bar" => "world"}`

      def index(conn, params) do
        posts =
          build_post_query(params)
          |> Repo.all()

        json(conn, posts)
      end

  ## Options

  * `with` - the model used for the query builder
  * `whitelist` - a list of allowable fields that can be queried,
  if this option is defined any fields not included will be ignored
  during the query builder. If this option is omitted all fields will be
  queried.

  ## Writing custom query handlers

  The key/value pairs are iterated over recursively as the query is
  built up. A default handler that simply add `where(key = value)` to
  the query can be overriden for each key. You can pattern match on the
  key name to override:

      def build_post_query(query, [{"title", title}|tail]) do
        new_query = # your custom query
        build_post_query(new_query, tail)
      end

  Ensure the new query and the tail of the params list is passed into
  the query builder function to continue the iteration. However, if
  you'd like to stop iteration just return the new query.
  """
  defmacro __using__(opts) do
    quote do
      @__inquisitor__model__ unquote(opts[:with])
      @__inquisitor__whitelist__ unquote(opts[:whitelist])
      @before_compile Inquisitor
    end
  end

  defmacro __before_compile__(env) do
    model     = Module.get_attribute(env.module, :__inquisitor__model__)
    whitelist = Module.get_attribute(env.module, :__inquisitor__whitelist__)
    fn_name   = :"build_#{name_from_model(model)}_query"

    quote do
      def unquote(fn_name)(params) do
        list =
          params
          |> Map.to_list()
          |> Inquisitor.whitelist_filter(unquote(whitelist))
          |> Inquisitor.preprocess()
        unquote(fn_name)(unquote(model), list)
      end

      def unquote(fn_name)(query, []), do: query
      def unquote(fn_name)(query, [{attr, value}|tail]) do
        query
        |> where([r], field(r, ^String.to_existing_atom(attr)) == ^value)
        |> unquote(fn_name)(tail)
      end
    end
  end

  def preprocess([]), do: []
  def preprocess([{attr, value}|tail]) when value == "true" or value == "false" do
    Ecto.Type.cast(:boolean, value)
    |> elem(1)
    |> (&preprocess([{attr, &1} | tail])).()
  end
  def preprocess([{attr, value}|tail]),
    do: [{attr, value} | preprocess(tail)]

  def whitelist_filter(params, nil), do: params
  def whitelist_filter(params, whitelist) do
    Enum.filter(params, &Enum.member?(whitelist, elem(&1, 0)))
  end

  defp name_from_model(model) do
    model
    |> Code.eval_quoted()
    |> elem(0)
    |> inspect()
    |> String.split(".")
    |> List.last()
    |> Mix.Utils.underscore()
  end
end
