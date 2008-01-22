import osrf.ses
import oils.event, oils.const

class OrgUtil(object):
    ''' Collection of general purpose org_unit utility functions '''

    _org_tree = None  
    _org_types = None  
    _flat_org_tree = {}

    @staticmethod
    def fetch_org_tree():
        ''' Returns the whole org_unit tree '''

        if OrgUtil._org_tree:
            return OrgUtil._org_tree

        tree = osrf.ses.ClientSession.atomic_request(
            oils.const.OILS_APP_ACTOR,
            'open-ils.actor.org_tree.retrieve')

        oils.event.Event.parse_and_raise(tree)
        OrgUtil._org_tree = tree
        OrgUtil.flatten_org_tree(tree)
        return tree

    @staticmethod
    def flatten_org_tree(node):
        ''' Creates links from an ID-based hash to the org units in the org tree '''
        if not node:
            node = OrgUtil._org_tree
        OrgUtil._flat_org_tree[node.id()] = node
        for child in node.children():
            OrgUtil.flatten_org_tree(child)
        

    @staticmethod
    def fetch_org_types():
        ''' Returns the list of org_unit_type objects '''

        if OrgUtil._org_types:
            return OrgUtil._org_types

        types = osrf.ses.ClientSession.atomic_request(
            oils.const.OILS_APP_ACTOR, 'open-ils.actor.org_types.retrieve')

        oils.event.Event.parse_and_raise(types)
        OrgUtil._org_types = types
        return types


    @staticmethod
    def get_org_type(org_unit):
        ''' Given an org_unit, this returns the org_unit_type object it's linked to '''
        types = OrgUtil.fetch_org_types()
        return [t for t in types if t.id() == org_unit.ou_type()][0]


    @staticmethod
    def get_related_tree(org_unit):
        ''' Returns a cloned tree of orgs including all ancestors and 
            descendants of the provided org '''

        org = org_unit = org_unit.shallow_clone()
        while org.parent_ou():
            parent = org.parent_ou()
            if not isinstance(parent, osrf.net_obj.NetworkObject):
                parent = OrgUtil._flat_org_tree[parent]
            parent = parent.shallow_clone()
            parent.children([org])
            org = parent
        root = org

        def trim_org(node):
            node = node.shallow_clone()
            children = node.children()
            if len(children) > 0:
                node.children([])
                for child in children:
                    node.children().append(trim_org(child))
            return node

        trim_org(org_unit)
        return root

    @staticmethod
    def debug_org(org_unit, indent=0):
        ''' Simple function to print the tree of orgs provided '''
        import sys
        for i in range(indent):
            sys.stdout.write('-')
        print org_unit.shortname()
        indent += 1
        for child in org_unit.children():
            OrgUtil.debug_org(child, indent)
        

