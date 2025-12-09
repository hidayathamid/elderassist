import { useState } from "react";
import { Card, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Avatar } from "@/components/shared/Avatar";
import { StatusBadge } from "@/components/shared/StatusBadge";
import { BottomSheet } from "@/components/shared/BottomSheet";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { caregivers } from "@/data/mockData";
import { Search, Filter, Eye, Edit, MoreVertical, Star, CheckCircle, XCircle, Award, DollarSign, Calendar } from "lucide-react";

const AdminCaregivers = () => {
  const [searchQuery, setSearchQuery] = useState("");
  const [selectedCaregiver, setSelectedCaregiver] = useState<typeof caregivers[0] | null>(null);

  const filteredCaregivers = caregivers.filter(cg =>
    cg.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
    cg.specialization.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-foreground">Caregivers</h1>
          <p className="text-muted-foreground">Manage registered caregivers and their profiles</p>
        </div>
        <Button>Add Caregiver</Button>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-4 gap-4">
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-foreground">85</p>
          <p className="text-sm text-muted-foreground">Total Caregivers</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-success">62</p>
          <p className="text-sm text-muted-foreground">Online Now</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-primary">78</p>
          <p className="text-sm text-muted-foreground">Verified</p>
        </Card>
        <Card variant="default" padding="sm">
          <p className="text-2xl font-bold text-warning">7</p>
          <p className="text-sm text-muted-foreground">Pending Verification</p>
        </Card>
      </div>

      {/* Search and Filters */}
      <Card variant="default" padding="sm">
        <div className="flex items-center gap-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search by name or specialization..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="pl-10"
            />
          </div>
          <Button variant="outline">
            <Filter className="h-4 w-4 mr-2" />
            Filters
          </Button>
        </div>
      </Card>

      {/* Caregivers Table */}
      <Card variant="default" padding="none">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Caregiver</TableHead>
              <TableHead>Specialization</TableHead>
              <TableHead>Rating</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Verification</TableHead>
              <TableHead>Jobs</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {filteredCaregivers.map((caregiver) => (
              <TableRow key={caregiver.id}>
                <TableCell>
                  <div className="flex items-center gap-3">
                    <Avatar 
                      src={caregiver.photo} 
                      name={caregiver.name} 
                      size="sm" 
                      status={caregiver.available ? "online" : "offline"}
                    />
                    <div>
                      <p className="font-medium text-foreground">{caregiver.name}</p>
                      <p className="text-xs text-muted-foreground">{caregiver.experience}</p>
                    </div>
                  </div>
                </TableCell>
                <TableCell>
                  <Badge variant="secondary">{caregiver.specialization}</Badge>
                </TableCell>
                <TableCell>
                  <div className="flex items-center gap-1">
                    <Star className="h-4 w-4 text-warning fill-warning" />
                    <span className="font-medium">{caregiver.rating}</span>
                  </div>
                </TableCell>
                <TableCell>
                  <StatusBadge status={caregiver.available ? "online" : "offline"} />
                </TableCell>
                <TableCell>
                  <Badge variant="success" className="gap-1">
                    <CheckCircle className="h-3 w-3" />
                    Verified
                  </Badge>
                </TableCell>
                <TableCell>
                  <span className="font-medium">{caregiver.completedJobs}</span>
                </TableCell>
                <TableCell className="text-right">
                  <div className="flex items-center justify-end gap-2">
                    <Button variant="ghost" size="iconSm" onClick={() => setSelectedCaregiver(caregiver)}>
                      <Eye className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="iconSm">
                      <Edit className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="iconSm">
                      <MoreVertical className="h-4 w-4" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </Card>

      {/* Caregiver Details Sheet */}
      <BottomSheet
        open={!!selectedCaregiver}
        onClose={() => setSelectedCaregiver(null)}
        title="Caregiver Details"
        height="full"
      >
        {selectedCaregiver && (
          <div className="space-y-6">
            {/* Profile */}
            <div className="flex items-center gap-4">
              <Avatar 
                src={selectedCaregiver.photo} 
                name={selectedCaregiver.name} 
                size="xl" 
                status={selectedCaregiver.available ? "online" : "offline"}
              />
              <div>
                <h3 className="text-xl font-bold text-foreground">{selectedCaregiver.name}</h3>
                <p className="text-muted-foreground">{selectedCaregiver.specialization}</p>
                <div className="flex items-center gap-2 mt-1">
                  <Star className="h-4 w-4 text-warning fill-warning" />
                  <span className="font-medium">{selectedCaregiver.rating}</span>
                  <StatusBadge status={selectedCaregiver.available ? "online" : "offline"} />
                </div>
              </div>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-3 gap-3">
              <Card variant="default" padding="sm" className="text-center">
                <Calendar className="h-5 w-5 text-primary mx-auto mb-1" />
                <p className="text-xl font-bold text-foreground">{selectedCaregiver.completedJobs}</p>
                <p className="text-xs text-muted-foreground">Jobs</p>
              </Card>
              <Card variant="default" padding="sm" className="text-center">
                <DollarSign className="h-5 w-5 text-success mx-auto mb-1" />
                <p className="text-xl font-bold text-foreground">RM 12,400</p>
                <p className="text-xs text-muted-foreground">Earnings</p>
              </Card>
              <Card variant="default" padding="sm" className="text-center">
                <Award className="h-5 w-5 text-warning mx-auto mb-1" />
                <p className="text-xl font-bold text-foreground">{selectedCaregiver.experience}</p>
                <p className="text-xs text-muted-foreground">Experience</p>
              </Card>
            </div>

            {/* Certifications */}
            <Card variant="outline" padding="sm">
              <h4 className="font-semibold text-foreground mb-3">Certifications</h4>
              <div className="flex flex-wrap gap-2">
                <Badge variant="success" className="gap-1">
                  <Award className="h-3 w-3" />
                  First Aid
                </Badge>
                <Badge variant="success" className="gap-1">
                  <Award className="h-3 w-3" />
                  CPR Certified
                </Badge>
                <Badge variant="success" className="gap-1">
                  <Award className="h-3 w-3" />
                  Elderly Care
                </Badge>
              </div>
            </Card>

            {/* Verification Status */}
            <Card variant="success" padding="sm">
              <div className="flex items-center gap-3">
                <CheckCircle className="h-6 w-6 text-success" />
                <div>
                  <p className="font-semibold text-foreground">Verified Caregiver</p>
                  <p className="text-sm text-muted-foreground">All documents verified on Dec 1, 2024</p>
                </div>
              </div>
            </Card>

            {/* Actions */}
            <div className="flex gap-3">
              <Button variant="outline" className="flex-1">View Schedule</Button>
              <Button variant="outline" className="flex-1">View Reviews</Button>
            </div>
            <Button variant="emergency" size="full">Suspend Caregiver</Button>
          </div>
        )}
      </BottomSheet>
    </div>
  );
};

export default AdminCaregivers;
