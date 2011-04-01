/* Copyright (C) 2011 The giomm Development Team
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free
 * Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

/* This is a basic server providing a clock like functionality.  Clients can
 * get the current time, set the alarm and get notified when the alarm time is
 * reached.  It is basic because there is only one global alarm which any
 * client can set.  Clients listening for the alarm signal will be notified by
 * use of the global alarm signal.  The server should be easily modifiable to
 * allow per-client alarms, but that is left as an exercise.
 *
 * Along with the above it provides a method to get its stdout's file
 * descriptor to test the Gio::DBus::Message API.
 */

#include <giomm.h>
#include <glibmm.h>
#include <iostream>

namespace
{

static Glib::RefPtr<Gio::DBus::NodeInfo> introspection_data;

static Glib::ustring introspection_xml =
  "<node>"
  "  <interface name='org.glibmm.DBus.Clock'>"
  "    <method name='GetTime'>"
  "      <arg type='s' name='iso8601' direction='out'/>"
  "    </method>"
  "    <method name='SetAlarm'>"
  "      <arg type='s' name='iso8601' direction='in'/>"
  "    </method>"
  "  </interface>"
  "</node>";

// Stores the current alarm.
static Glib::TimeVal curr_alarm;

// This variable is used to keep an incoming connection active until it is
// closed.
static Glib::RefPtr<Gio::DBus::Connection> current_connection;

} // anonymous namespace

static void on_method_call(const Glib::RefPtr<Gio::DBus::Connection>& connection,
  const Glib::ustring& /* sender */, const Glib::ustring& /* object_path */,
  const Glib::ustring& /* interface_name */, const Glib::ustring& method_name,
  const Glib::VariantContainerBase& parameters,
  const Glib::RefPtr<Gio::DBus::MethodInvocation>& invocation)
{
  if(method_name == "GetTime")
  {
    Glib::TimeVal curr_time;
    curr_time.assign_current_time();

    const Glib::ustring time_str = curr_time.as_iso8601();
    const Glib::Variant<Glib::ustring> time_var =
      Glib::Variant<Glib::ustring>::create(time_str);

    // Create the tuple.
    Glib::VariantContainerBase response =
      Glib::VariantContainerBase::create_tuple(time_var);

    // Return the tuple with the included time.
    invocation->return_value(response);
  }
  else if(method_name == "SetAlarm")
  {
    // Get the parameter tuple.
    //Glib::VariantContainerBase parameters;
    //invocation->get_parameters(parameters);

    // Get the variant string.
    Glib::Variant<Glib::ustring> param;
    parameters.get_child(param);

    // Get the time string.
    const Glib::ustring time_str = param.get();

    if(!curr_alarm.assign_from_iso8601(time_str))
    {
      // If setting alarm was not successful, return an error.
      Gio::DBus::Error error(Gio::DBus::Error::INVALID_ARGS,
          "Alarm string is not in ISO8601 format.");
      invocation->return_error(error);
    }
  }
  else if(method_name == "GetStdout")
  {
#ifndef G_OS_WIN32
    if(connection->get_capabilities() &
      Gio::DBus::CAPABILITY_FLAGS_UNIX_FD_PASSING)
    {
      Glib::RefPtr<Gio::UnixFDList> list = Gio::UnixFDList::create();
      try
      {
        list->append(STDOUT_FILENO);

        Glib::RefPtr<Gio::DBus::Message> reply =
          Gio::DBus::Message::create_method_reply(invocation->get_message());

        reply->set_unix_fd_list(list);

        connection->send_message(reply);
      }
      catch(const Glib::Error& ex)
      {
        std::cerr << "Error trying to send stdout to client: " << ex.what() <<
          std::endl;
        return;
      }
    }
    else
    {
      invocation->return_dbus_error("org.glibmm.DBus.Failed", "Your message "
        "bus daemon does not support file descriptor passing (need D-Bus >= "
        "1.3.0)");
    }
#else
    invocation->return_dbus_error("org.glibmm.DBus.Failed", "Your message bus "
      "daemon does not support file descriptor passing (need D-Bus >= 1.3.0)");
#endif
  }
  else
  {
    // Non-existent method on the interface.
    Gio::DBus::Error error(Gio::DBus::Error::UNKNOWN_METHOD,
      "Method does not exist.");
    invocation->return_error(error);
  }
}

//This must be a global instance. See the InterfaceVTable documentation.
//TODO: Make that unnecessary.
const Gio::DBus::InterfaceVTable interface_vtable(sigc::ptr_fun(&on_method_call));

bool on_server_new_connection(const Glib::RefPtr<Gio::DBus::Connection>& connection)
{
  Glib::RefPtr<Gio::Credentials> credentials =
    connection->get_peer_credentials();

  std::string credentials_str;

  if(!credentials)
    credentials_str = "(no credentials received)";
  else
    credentials_str = credentials->to_string();

  std::cout <<
    "Client connected." << std::endl <<
    "Peer credentials: " << credentials_str << std::endl <<
    "Negotiated capabilities: unix-fd-passing=" << (connection->get_capabilities() & Gio::DBus::CAPABILITY_FLAGS_UNIX_FD_PASSING) << std::endl;

  // If there is already an active connection, do not accept this new one.
  // There may be a better way to decide how to keep current incoming
  // connections.
  if(current_connection && !current_connection->is_closed())
  {
    std::cerr << "Unable to accept a new incoming connection because one is "
      "already active." << std::endl;

    return false;
  }

  // In order for the connection to stay active the reference to the
  // connection must be kept, so store the connection in a global variable:
  current_connection = connection;

  // See https://bugzilla.gnome.org/show_bug.cgi?id=646417 about avoiding
  // the repetition of the interface name:
  try
  {
    connection->register_object("/org/glibmm/DBus/TestObject",
      introspection_data->lookup_interface("org.glibmm.DBus.Clock"),
      interface_vtable);
  }
  catch(const Glib::Error& ex)
  {
    std::cerr << "Registration of object failed." << std::endl;
    return false;
  }

  return true;
}

int main(int, char**)
{
  std::locale::global(std::locale(""));
  Gio::init();

 try
  {
    introspection_data = Gio::DBus::NodeInfo::create_for_xml(introspection_xml);
  }
  catch(const Glib::Error& ex)
  {
    std::cerr << "Unable to create introspection data: " << ex.what() <<
      "." << std::endl;
    return 1;
  }

  Glib::RefPtr<Gio::DBus::Server> server;

  const Glib::ustring address = "unix:abstract=myadd";
  try
  {
    server = Gio::DBus::Server::create_sync(address,
      Gio::DBus::generate_guid());
  }
  catch(const Glib::Error& ex)
  {
    std::cerr << "Error creating server at address: " << address <<
      ": " << ex.what() << "." << std::endl;
    return EXIT_FAILURE;
  }

  server->start();

  std::cout << "Server is listening at: " << server->get_client_address() <<
    "." << std::endl;

  server->signal_new_connection().connect(sigc::ptr_fun(&on_server_new_connection));

  //Keep the server running until the process is killed:
  Glib::RefPtr<Glib::MainLoop> loop = Glib::MainLoop::create();
  loop->run();

  return EXIT_SUCCESS;
}
