# -*- mode: perl; perl-indent-level: 2; indent-tabs-mode: nil -*-
# gmmproc - Common::Output::Misc module
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

package Common::Output::Misc;

use strict;
use warnings;

sub nl
{
  return Common::Output::Shared::nl @_;
}

sub p_include ($$)
{
  my ($wrap_parser, $include) = @_;

  unless (Common::Output::Shared::already_included $wrap_parser, $include)
  {
    my $section_manager = $wrap_parser->get_section_manager;
    my $section = Common::Output::Shared::get_section $wrap_parser, Common::Sections::P_H_INCLUDES;
    my $code_string = (nl '#include <', $include, '>');

    $section_manager->append_string_to_section ($code_string, $section);
  }
}

1; # indicate proper module load.
