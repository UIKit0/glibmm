# -*- mode: perl; perl-indent-level: 2; indent-tabs-mode: nil -*-
# gmmproc - Common::Output::OpaqueCopyable module
#
# Copyright 2012 glibmm development team
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307, USA.
#

package Common::Output::OpaqueCopyable;

use strict;
use warnings;

sub nl
{
  return Common::Output::Shared::nl @_;
}

sub _output_h_in_class ($$$)
{
  my ($wrap_parser, $c_type, $cxx_type) = @_;
  my $section_manager = $wrap_parser->get_section_manager;
  my $code_string = nl ('public:') .
                    nl (Common::Output::Shared::doxy_skip_begin) .
                    nl ('  typedef ' . $cxx_type . ' CppObjectType;') .
                    nl ('  typedef ' . $c_type . ' BaseObjectType;') .
                    nl (Common::Output::Shared::doxy_skip_end) .
                    nl ();
  my $main_section = $wrap_parser->get_main_section;

  $section_manager->push_section ($main_section);
  $section_manager->append_string ($code_string);

  my $conditional = Common::Output::Shared::default_ctor_proto $wrap_parser, $cxx_type;

  $section_manager->append_conditional ($conditional);

  my $copy_proto = 'const';
  my $reinterpret = 0;
  my $definitions = 1;
  my $virtual_dtor = 0;

  $code_string = nl ('  // Use make_a_copy = true when getting it directly from a struct.') .
                 nl ('  explicit ' . $cxx_type . '(' . $c_type . '* castitem, bool make_a_copy = false);') .
                 nl () .
                 nl (Common::Output::Shared::copy_protos_str $cxx_type) .
                 nl () .
                 nl (Common::Output::Shared::dtor_proto_str $cxx_type, $virtual_dtor) .
                 nl () .
                 nl (Common::Output::Shared::gobj_protos_str $c_type, $copy_proto, $reinterpret, $definitions) .
                 nl () .
                 nl ('protected:') .
                 nl ('  ' . $c_type . '* gobject_;') .
                 nl () .
                 nl ('private:');
  $section_manager->append_string ($code_string);
  $section_manager->pop_entry;
}

sub _output_h_after_first_namespace ($$)
{
  my ($wrap_parser, $c_type) = @_;
  my $section_manager = $wrap_parser->get_section_manager;
  my $result_type = 'plain';
  my $take_copy_by_default = 'no';
  my $open_glib_namespace = 1;
  my $const_function = 0;
  my $conditional = Common::Output::Shared::wrap_proto $wrap_parser, $c_type, $result_type, $take_copy_by_default, $open_glib_namespace, $const_function;
  my $section = Common::Output::Shared::get_section $wrap_parser, Common::Sections::H_AFTER_FIRST_NAMESPACE;

  $section_manager->append_conditional_to_section ($conditional, $section);
}

sub _output_cc ($$$$$$)
{
  my ($wrap_parser, $c_type, $cxx_type, $new_func, $copy_func, $free_func) = @_;
  my $section_manager = $wrap_parser->get_section_manager ();
  my $custom_default_ctor_var = Common::Output::Shared::get_variable ($wrap_parser, Common::Variables::CUSTOM_DEFAULT_CTOR);
  my $conditional = Common::Output::Shared::generate_conditional ($wrap_parser);
  my $full_cxx_type = Common::Output::Shared::get_full_cxx_type ($wrap_parser);
  my $complete_cxx_type = Common::Output::Shared::get_complete_cxx_type ($wrap_parser);
  my $code_string = nl ('namespace Glib') .
                    nl ('{') .
                    nl () .
                    nl ($complete_cxx_type . ' wrap(' . $c_type . '* object, bool take_copy /* = false */)') .
                    nl ('{') .
                    nl ('  return ', $complete_cxx_type, '(object, take_copy);') .
                    nl ('}') .
                    nl () .
                    nl ('} // namespace Glib') .
                    nl ();
  my $no_wrap_function_var = Common::Output::Shared::get_variable ($wrap_parser, Common::Variables::NO_WRAP_FUNCTION);
  my $section = Common::Output::Shared::get_section ($wrap_parser, Common::Sections::CC_GENERATED);

  $section_manager->append_string_to_conditional ($code_string, $conditional, 0);
  $section_manager->push_section ($section);
  $section_manager->append_conditional ($conditional);
  $section_manager->set_variable_for_conditional ($no_wrap_function_var, $conditional);

  $conditional = Common::Output::Shared::generate_conditional ($wrap_parser);
  $code_string = Common::Output::Shared::open_namespaces ($wrap_parser) .
                 nl ($full_cxx_type . '::' . $cxx_type . '()') .
                 nl (':');

  if (defined $new_func and $new_func ne '' and $new_func ne 'NONE')
  {
    $code_string .= nl ('  gobject_(' . $new_func . '())');
  }
  else
  {
    $code_string .= nl ('  gobject_(0) // Allows creation of invalid wrapper, e.g. for output arguments to methods.');
  }
  $code_string .= nl ('{}') .
                  nl ();
  $section_manager->append_string_to_conditional ($code_string, $conditional, 0);
  $section_manager->append_conditional ($conditional);
  $section_manager->set_variable_for_conditional ($custom_default_ctor_var, $conditional);
# TODO: we probably have to assume that copy func must be provided.
  $code_string = nl ($full_cxx_type . '::' . $cxx_type . '(const ' . $cxx_type . '& src)') .
                 nl (':') .
                 nl ('  gobject_((src.gobject_) ? ' . $copy_func . '(src.gobject_) : 0)') .
                 nl ('{}') .
                 nl () .
                 nl ($full_cxx_type . '::' . $cxx_type . '(' . $c_type . '* castitem, bool make_a_copy /* = false */)') .
                 nl ('{') .
                 nl ('  if (!make_a_copy)') .
                 nl ('  {') .
                 nl ('    // It was given to use by a function which has already made a copy for us to keep.') .
                 nl ('    gobject_ = castitem;') .
                 nl ('  }') .
                 nl ('  else') .
                 nl ('  {') .
                 nl ('    // We are probably getting it via direct access to a struct,') .
                 nl ('    // so we can not just take ut - we have to take a copy if it.') .
                 nl ('    if (castitem)') .
                 nl ('    {') .
                 nl ('      gobject_ = ' . $copy_func . '(castitem);') .
                 nl ('    }') .
                 nl ('    else') .
                 nl ('    {') .
                 nl ('      gobject_ = 0;') .
                 nl ('    }') .
                 nl ('  }') .
                 nl ('}') .
                 nl ();
  if (defined $copy_func and $copy_func ne '' and $copy_func ne 'NONE')
  {
    $code_string .= nl ($full_cxx_type . '& ' . $full_cxx_type . '::operator=(const ' . $full_cxx_type . '& src)') .
                    nl ('{') .
                    nl ('  ' . $c_type . '* const new_gobject = (src.gobject_) ? ' . $copy_func . '(src.gobject_) : 0;') .
                    nl () .
                    nl ('  if (gobject_)') .
                    nl ('  {') .
                    nl ('    ' . $free_func . '(gobject_);') .
                    nl ('  }') .
                    nl () .
                    nl ('  gobject_ = new_gobject;') .
                    nl () .
                    nl ('  return *this;') .
                    nl ('}') .
                    nl ();
  }
  $code_string .= nl ($full_cxx_type . '::~' . $cxx_type . '()') .
                  nl ('{') .
                  nl ('  if (gobject_)') .
                  nl ('  {') .
                  nl ('    ' . $free_func . '(gobject_);') .
                  nl ('  }') .
                  nl ('}') .
                  nl () .
                  nl ($c_type . '* ' . $full_cxx_type . '::gobj_copy() const') .
                  nl ('{') .
                  nl ('  return ' . $copy_func . '(gobject_);') .
                  nl ('}') .
                  nl ();
  $section_manager->append_string ($code_string);

  my $cc_namespace_section = Common::Output::Shared::get_section $wrap_parser, Common::Sections::CC_NAMESPACE;

  $section_manager->append_section ($cc_namespace_section);
  $code_string = nl () .
                 Common::Output::Shared::close_namespaces $wrap_parser;
  $section_manager->append_string ($code_string);
  $section_manager->pop_entry;
}

sub output ($$$$$$)
{
  my ($wrap_parser, $c_type, $cxx_type, $new_func, $copy_func, $free_func) = @_;

  _output_h_in_class $wrap_parser, $c_type, $cxx_type;
  _output_h_after_first_namespace $wrap_parser, $c_type;
  _output_cc $wrap_parser, $c_type, $cxx_type, $new_func, $copy_func, $free_func;
}

1; # indicate proper module load.
