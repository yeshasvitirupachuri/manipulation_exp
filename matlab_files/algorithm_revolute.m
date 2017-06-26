close all;
clear all; 
clc; 

filename = '/home/yeshi/projects/manipulation_exp/manipulation/data/rmotion2.txt';
data = importdata(filename);
% data=data1(14600:17000,:);
t = data(:,1); %%Time received in seconds
t = t - t(1,1); %%Corrected to zero
dt = diff(t); %%dt
dt=[0;dt];
dt2 = diff(t(2:end)); %%dt2
dt2 = [0;0;dt2];

%%Pose Values - Angular part is quaternion
pose_1 = data(:,2:8);
pose_2 = data(:,9:15);

%%Interaction Wrench - Measured in local frame
left_wrench = data(:,16:21); %%FT at Body1
right_wrench = data(:,22:27); %%FT at Body2

%%Rigid Body Properties
m1 = 1; %%Kgs
I_c1 = [0.00025   0         0;
        0         0.00324   0;
        0         0         0.0034]; %%Inertia at CoM - taken from  SDF
com1 = [0.1; 0; 0];

m2 = 1; %%Kgs
I_c2 = I_c1; %%Inertia at CoM - taken from  SDF
com2 = [0.15; 0; 0];

%%Spatial Inertia in Body Frame
M_1 = spatialInertia(m1,I_c1,com1);
M_2 = spatialInertia(m2,I_c2,com2);

for i=1:1:size(t,1)
    
    T_A_1 = transformH(pose_1(i,:));
    T_A_2 = transformH(pose_2(i,:));
    
    T_1_2 = inv(T_A_1)*(T_A_2);
%     X_1_2 = transformX(T_1_2);
    
    %%Joint Quantities
    P_1_2 = linear(T_1_2);   
    d(i,:) = norm(P_1_2); %%Prismatic Distance
    
    %%Logic to remove NaN values
    if d(i,:) == 0
        Sp(i,:) = [0;0;0;0;0;0];
    else
        Sp(i,:) = [(P_1_2/d(i,:));0;0;0];
    end
    
% %     if d(i,:) <= 0.01
% %         d(i,:) = 0;
% %         Sp(i,:) = [0;0;0;0;0;0]; %%This is setting the axis to zero - meaning Fixed joint
% %         %%Sp(i,:) = [0;0;1;0;0;0]; %%This is setting axis to y direction
% %     else
% %         Sp(i,:) = [P_1_2/(d(i,:));0;0;0]; %%Prismatic axis - TODO: Change in the algorithm
% %     end
    
    R_1_2 = rot(T_1_2);
    axisAngleVector = vrrotmat2vec(R_1_2);
    theta(i,:) = axisAngleVector(4);
    Sr(i,:) = [0;0;0;axisAngleVector(1:3)'];
    
    %%Computing Joint Velocity
    if i == 1
        dd(i,:) = 0;
        dtheta(i,:) = 0;
    else
        dd(i,:) = (d(i,:)-d(i-1,:))/dt(i);
        dtheta(i,:) = (theta(i,:)-theta(i-1,:))/dt(i);    
    end
    
    %%Joint Velocity wrt first link frame
    V_PJ(i,:) = (Sp(i,:)')*dd(i,:);
    V_RJ(i,:) = (Sr(i,:)')*dtheta(i,:);
    
    %%Joint Velocity wrt inertial frame
    V_A_PJ(i,:) = transformX(T_A_1)*(Sp(i,:)')*dd(i,:);
    V_A_RJ(i,:) = transformX(T_A_1)*(Sr(i,:)')*dtheta(i,:);
    
    %%Body 1 Velocity
    P_A_1(i,:) = linear(T_A_1);
    R_A_1(i).R = rot(T_A_1);
    if i == 1
        V_A_1(i,:) = zeros(6,1);
    else
        v_A_1 = (P_A_1(i,:) - P_A_1(i-1,:))/dt(i);
        dRot_A_1 = (R_A_1(i).R - R_A_1(i-1).R)/dt(i);
        omega_A_1 = skew2vec(dRot_A_1*R_A_1(i).R);
        V_A_1(i,:) = [v_A_1 omega_A_1];
    end
    
    %%Computing Body 2 Velocity
    V_A_P2(i,:) = V_A_1(i,:) + V_A_PJ(i,:);
    V_A_R2(i,:) = V_A_1(i,:) + V_A_RJ(i,:);
    
    %%Computing Spatial Inertia
    M_A_1 = transformXstar(T_A_1)*M_1*inv(transformX(T_A_1)); %%This is the same as transformX(inv(T))
    M_A_2 = transformXstar(T_A_2)*M_2*inv(transformX(T_A_2));
    
    %%Total momentum of the system
    h2P(i,:) = M_A_2 * V_A_P2(i,:)';
    h2R(i,:) = M_A_2 * V_A_R2(i,:)';
    
    h_A_P(i,:) = M_A_1 * V_A_1(i,:)' + M_A_2 * V_A_P2(i,:)';
    h_A_R(i,:) = M_A_1 * V_A_1(i,:)' + M_A_2 * V_A_R2(i,:)';
    
    %%Rate of change in momentum
    if i == 1 
        dh_A_P(i,:) = zeros(6,1);
        dh_A_R(i,:) = zeros(6,1);
    else
        dh_A_P(i,:) = (h_A_P(i,:) - h_A_P(i-1,:))/dt(i);
        dh_A_R(i,:) = (h_A_R(i,:) - h_A_R(i-1,:))/dt(i);
    end
    
    %%Modifying torques
    momentArm = [0.275*cos(theta(i,:)); 0.275*sin(theta(i,:)); 0];
    left_wrench(i,4:6) = vec2skew(left_wrench(i,1:3)')*momentArm;
    left_wrench(i,1:3) = zeros(1,3);
    
    right_wrench(i,4:6) = vec2skew(right_wrench(i,1:3)')*momentArm;
    right_wrench(i,1:3) = zeros(1,3);
    
    %%Computing External Wrench
    ft2_offset = 0.275; %%NOTE: This theta angle is w.r.t the first link, but it has to be gotten w.r.t the world
    F_A_1(i,:) = transformFT(T_A_1,[0;0;0])*left_wrench(i,:)';
    F_A_2(i,:) = transformFT(T_A_2,[ft2_offset*cos(theta(i,:));ft2_offset*sin(theta(i,:));0])*right_wrench(i,:)';
    W_A(i,:) = F_A_1(i,:) + F_A_2(i,:);
    
    %%Hypothesis Computation
    P(i,:) = W_A(i,:) - dh_A_P(i,:);
    R(i,:) = W_A(i,:) - dh_A_R(i,:);
    
% %     pause;
end

Phyp = sum(P.*P)
Rhyp = sum(R.*R)

%%Joint Angle radians to angles
theta = theta*(180/pi);

% % % % %%Figures
% % % % %%Joint Variables
% % figure;
% % subplot(2,1,1); plot(t,d); title('Joint Distance');  xlabel('sec');
% % subplot(2,1,2); plot(t,theta); title('Joint Angle');  xlabel('sec');
% % 
% % %%Joint Axes
% % figure;
% % subplot(2,1,1); plot(t,Sp); title('Prismatic Joint Axes');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % subplot(2,1,2); plot(t,Sr); title('Revolute Joint Axes');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % 
% % %%Joint Velocity
% % figure;
% % subplot(2,1,1); plot(t,V_A_PJ); title('Prismatic Joint Velocity');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % subplot(2,1,2); plot(t,V_A_RJ); title('Revolute Joint Velocity');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % 
% % %%Body 2 Velocity
% % figure;
% % subplot(3,1,1); plot(t,V_A_1); title('Body1 Velocity');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % subplot(3,1,2); plot(t,V_A_P2); title('Prismatic Body2 Velocity');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % subplot(3,1,3); plot(t,V_A_R2); title('Revolute Body2 Velocity');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % 
% % %%Total Momentum
% % figure;
% % subplot(2,1,1); plot(t,h2P); title('Prismatic - Body2 Momentum');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % subplot(2,1,2); plot(t,h2R); title('Revolute - Body2 Momentum');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % 
% % % % figure;
% % % % subplot(2,1,1); plot(t,h_A_P); title('Prismatic - Total Momentum');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % % % subplot(2,1,2); plot(t,h_A_R); title('Revolute - Total Momentum');  xlabel('sec'); legend('d_x','d_y','d_z','d_{ox}','d_{oy}','d_{oz}')
% % 
%%Wrench - Local Frame
figure;
subplot(2,1,1); plot(t,left_wrench); title('FT1 Local Frame');  xlabel('sec'); legend('e_{ox}','e_{oy}','e_{oz}','e_x','e_y','e_z');
subplot(2,1,2); plot(t,right_wrench); title('FT2 Local Frame');  xlabel('sec'); legend('e_{ox}','e_{oy}','e_{oz}','e_x','e_y','e_z');

%%Wrench - Inertial Frame
figure;
subplot(3,1,1); plot(t,F_A_1); title('FT1 Inertial Frame');  xlabel('sec'); legend('e_{ox}','e_{oy}','e_{oz}','e_x','e_y','e_z');
subplot(3,1,2); plot(t,F_A_2); title('FT2 Inertial Frame');  xlabel('sec'); legend('e_{ox}','e_{oy}','e_{oz}','e_x','e_y','e_z');
subplot(3,1,3); plot(t,W_A); title('Total Wrench');  xlabel('sec'); legend('e_{ox}','e_{oy}','e_{oz}','e_x','e_y','e_z');
% % 
% %  %%Joint Hypothesis
% % figure;
% % subplot(2,1,1); plot(t,P); title('Prismatic Hypothesis');  xlabel('sec');
% % subplot(2,1,2); plot(t,R); title('Revolute Hypothesis');  xlabel('sec');