#######################################################################
# Copyright (c) 2024 ENEO Tecnologia S.L.
# This file is part of redBorder.
# redBorder is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# redBorder is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# You should have received a copy of the GNU Affero General Public License
# along with redBorder. If not, see <http://www.gnu.org/licenses/>.
#######################################################################

import json
from pyattck import Attck

attack = Attck()

data = []

for tactic in attack.enterprise.tactics:
    tactic_data = {
        "Tactic": tactic.name,
        "ID": tactic.external_references[0].external_id,
        "Techniques": [],
        "Description": tactic.description
    }

    for technique in tactic.techniques:
        technique_id = technique.technique_id
        if "." not in technique_id:
            technique_data = {
                "Technique": technique.name,
                "ID": technique_id,
                "Subtechniques": [],
                "Description": technique.description
            }

            if hasattr(technique, 'techniques'):
                for subtechnique in technique.techniques:
                    subtechnique_id = subtechnique.technique_id
                    subtechnique_data = {
                        "Subtechnique": subtechnique.name,
                        "ID": subtechnique_id,
                        "ParentID": subtechnique.technique_id,
                        "Description": subtechnique.description
                    }
                    technique_data["Subtechniques"].append(subtechnique_data)
            else:
                technique_data["Subtechniques"].append("No subtechniques found")

            tactic_data["Techniques"].append(technique_data)

    data.append(tactic_data)

json_data = json.dumps(data, indent=4)

print(json_data)