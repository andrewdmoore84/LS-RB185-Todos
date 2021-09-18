require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "tilt/erubis"

class SessionPersistence
  def initialize(session)
    @session = session
    @session[:lists] ||= []
  end

  def change_list_name(list_id, new_name)
    list = get_list(list_id)
    list[:name] = new_name
  end

  def complete_list(list_id)
    list = get_list(list_id)

    list[:todos].each do |todo|
      todo[:completed] = true
    end
  end

  def create_new_list(list_name)
    id = next_element_id(lists)
    lists << { id: id, name: list_name, todos: [] }
  end

  def create_new_todo(list_id, todo_text)
    list = get_list(list_id)

    id = next_element_id(list[:todos])
    list[:todos] << { id: id, name: todo_text, completed: false }
  end

  def delete_list(id)
    lists.reject! { |list| list[:id] == id }
  end

  def delete_todo(list_id, todo_id)
    list = get_list(list_id)
    list[:todos].reject! { |todo| todo[:id] == todo_id }
  end

  def get_list(id)
    lists.find{ |list| list[:id] == id }
  end

  def list_name_taken?(list_name)
    lists.any? { |list| list[:name] == list_name }
  end

  def lists
    @session[:lists]
  end

  def error=(error_msg)
    @session[:error] = error_msg
  end

  def success=(success_msg)
    @session[:success] = success_msg
  end

  def update_todo(list_id, todo_id, is_completed)
    list = get_list(list_id)

    todo = list[:todos].find { |todo| todo[:id] == todo_id }
    todo[:completed] = is_completed
  end

  private

  def next_element_id(elements)
    max = elements.map { |todo| todo[:id] }.max || 0
    max + 1
  end
end

#######################################################
# Begin Sinatra code
#######################################################

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

helpers do
  def list_complete?(list)
    todos_count(list) > 0 && todos_remaining_count(list) == 0
  end

  def list_class(list)
    "complete" if list_complete?(list)
  end

  def todos_count(list)
    list[:todos].size
  end

  def todos_remaining_count(list)
    list[:todos].count { |todo| !todo[:completed] }
  end

  def sort_lists(lists, &block)
    complete_lists, incomplete_lists = lists.partition { |list| list_complete?(list) }

    incomplete_lists.each(&block)
    complete_lists.each(&block)
  end

  def sort_todos(todos, &block)
    complete_todos, incomplete_todos = todos.partition { |todo| todo[:completed] }

    incomplete_todos.each(&block)
    complete_todos.each(&block)
  end
end

def load_list(id)
  list = @storage.get_list(id)
  return list if list

  @storage.error = "The specified list was not found."
  redirect "/lists"
  halt
end

# Return an error message if the name is invalid. Return nil if name is valid.
def error_for_list_name(name)
  if !(1..100).cover? name.size
    "List name must be between 1 and 100 characters."
  elsif @storage.list_name_taken?(name)
    "List name must be unique."
  end
end

# Return an error message if the name is invalid. Return nil if name is valid.
def error_for_todo(name)
  if !(1..100).cover? name.size
    "Todo must be between 1 and 100 characters."
  end
end

before do
  @storage = SessionPersistence.new(session)
end

get "/" do
  redirect "/lists"
end

# View list of lists
get "/lists" do
  @lists = @storage.lists
  erb :lists, layout: :layout
end

# Render the new list form
get "/lists/new" do
  erb :new_list, layout: :layout
end

# Create a new list
post "/lists" do
  list_name = params[:list_name].strip

  error = error_for_list_name(list_name)
  if error
    @storage.error = error
    erb :new_list, layout: :layout
  else
    @storage.create_new_list(list_name)
    @storage.success = "The list has been created."
    redirect "/lists"
  end
end

# View a single todo list
get "/lists/:id" do
  @list_id = params[:id].to_i
  @list = @storage.get_list(@list_id)
  erb :list, layout: :layout
end

# Edit an existing todo list
get "/lists/:id/edit" do
  id = params[:id].to_i
  @list = @storage.get_list(id)
  erb :edit_list, layout: :layout
end

# Update an existing todo list
post "/lists/:id" do
  list_name = params[:list_name].strip
  id = params[:id].to_i
  @list = @storage.get_list(id)

  error = error_for_list_name(list_name)
  if error
    @storage.error = error
    erb :edit_list, layout: :layout
  else
    @storage.change_list_name(id, list_name)
    @storage.success = "The list has been updated."
    redirect "/lists/#{id}"
  end
end

# Delete a todo list
post "/lists/:id/destroy" do
  id = params[:id].to_i

  @storage.delete_list(id)
  @storage.success = "The list has been deleted."
  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    "/lists"
  else
    redirect "/lists"
  end
end

# Add a new todo to a list
post "/lists/:list_id/todos" do
  @list_id = params[:list_id].to_i
  text = params[:todo].strip

  error = error_for_todo(text)
  if error
    @storage.error = error
    erb :list, layout: :layout
  else
    @storage.create_new_todo(@list_id, text)

    @storage.success = "The todo was added."
    redirect "/lists/#{@list_id}"
  end
end

# Delete a todo from a list
post "/lists/:list_id/todos/:id/destroy" do
  @list_id = params[:list_id].to_i

  todo_id = params[:id].to_i
  @storage.delete_todo(@list_id, todo_id)

  if env["HTTP_X_REQUESTED_WITH"] == "XMLHttpRequest"
    status 204
  else
    @storage.success = "The todo has been deleted."
    redirect "/lists/#{@list_id}"
  end
end

# Update the status of a todo
post "/lists/:list_id/todos/:id" do
  @list_id = params[:list_id].to_i

  todo_id = params[:id].to_i
  is_completed = params[:completed] == "true"

  @storage.update_todo(@list_id, todo_id, is_completed)

  @storage.success = "The todo has been updated."
  redirect "/lists/#{@list_id}"
end

# Mark all todos as complete for a list
post "/lists/:id/complete_all" do
  @list_id = params[:id].to_i

  @storage.complete_list(@list_id)

  @storage.success = "All todos have been completed."
  redirect "/lists/#{@list_id}"
end